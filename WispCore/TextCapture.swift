import CoreGraphics
import Foundation

/// One line Vision read, with where it sits in the image.
public struct RecognizedLine: Equatable, Sendable {
    public let text: String
    /// Normalised to the image, origin at the bottom left (Vision's space).
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// Turns recognised lines into text to paste: reading order, paragraphs and tidy spacing.
public enum CapturedText {
    /// Rows top to bottom, words on a row left to right, a blank line where the gap between
    /// rows is taller than a line, and words split by a hyphen at a line end joined again.
    public static func join(_ lines: [RecognizedLine]) -> String {
        let kept = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sorted = kept.sorted { ($0.box.maxY, -$0.box.minX) > ($1.box.maxY, -$1.box.minX) }
        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let last = rows.last, let first = last.first, sameRow(first, line) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        var output: [String] = []
        var previous: CGRect?
        for row in rows {
            let text = row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
            let box = row.map(\.box).reduce(CGRect.null) { $0.union($1) }
            if let previous, previous.minY - box.maxY > min(previous.height, box.height) {
                output.append("")
            }
            output.append(text)
            previous = box
        }
        return clean(joiningHyphens(output).joined(separator: "\n"))
    }

    /// Single spaces, trimmed lines, at most one blank line in a row, none at either end.
    public static func clean(_ text: String) -> String {
        let normalised =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: " ")
        var lines: [String] = []
        for raw in normalised.components(separatedBy: "\n") {
            let line = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// "recog-" then "nised" becomes "recognised". A capital after the hyphen ("Wisp-" then
    /// "Core") is more likely a real hyphen, so it stays.
    static func joiningHyphens(_ lines: [String]) -> [String] {
        var output: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let last = output.last, endsInBrokenWord(last), trimmed.first?.isLowercase == true {
                output[output.count - 1] = String(last.trimmingCharacters(in: .whitespaces).dropLast()) + trimmed
            } else {
                output.append(line)
            }
        }
        return output
    }

    private static func endsInBrokenWord(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("-"), trimmed.count >= 2 else { return false }
        return trimmed.dropLast().last?.isLetter == true
    }

    /// Two lines share a row when they overlap by at least half the shorter one's height.
    private static func sameRow(_ a: RecognizedLine, _ b: RecognizedLine) -> Bool {
        let overlap = min(a.box.maxY, b.box.maxY) - max(a.box.minY, b.box.minY)
        return overlap > min(a.box.height, b.box.height) / 2
    }
}

/// What a QR code or barcode holds, as far as Wisp treats it differently.
public enum ScannedCode: Equatable, Sendable {
    /// A web address (http or https only; other schemes are copied as text, never opened).
    case link(URL)
    /// A Wi-Fi join code. Nil password for an open network.
    case wifi(network: String, password: String?)
    case text(String)

    public init?(payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        {
            self = .link(url)
        } else if let wifi = Self.wifi(trimmed) {
            self = wifi
        } else {
            self = .text(trimmed)
        }
    }

    /// What goes on the clipboard: the password for Wi-Fi, since that's what gets typed.
    public var copyText: String {
        switch self {
        case .link(let url): url.absoluteString
        case .wifi(let network, let password): password ?? network
        case .text(let text): text
        }
    }

    public var notice: String {
        switch self {
        case .link(let url):
            let host = url.host ?? url.absoluteString
            return "Copied link to \(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)"
        case .wifi(let network, nil): return "Copied network name; \(network) has no password"
        case .wifi(let network, _): return "Copied Wi-Fi password for \(network)"
        case .text: return "Copied code"
        }
    }

    /// `WIFI:T:WPA;S:name;P:password;;`, where `\` escapes `;`, `,`, `:`, `"` and itself.
    private static func wifi(_ payload: String) -> ScannedCode? {
        guard payload.uppercased().hasPrefix("WIFI:") else { return nil }
        var fields: [String: String] = [:]
        var current = ""
        var escaped = false
        func finishField() {
            if let colon = current.firstIndex(of: ":") {
                let key = current[..<colon].uppercased()
                if fields[key] == nil { fields[key] = unquoted(String(current[current.index(after: colon)...])) }
            }
            current = ""
        }
        for character in payload.dropFirst(5) {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == ";" {
                finishField()
            } else {
                current.append(character)
            }
        }
        finishField()
        guard let network = fields["S"], !network.isEmpty else { return nil }
        let open = fields["T"]?.lowercased() == "nopass"
        let password = fields["P"].flatMap { $0.isEmpty || open ? nil : $0 }
        return .wifi(network: network, password: password)
    }

    /// Some generators wrap values in double quotes (`P:"secret"`); the quotes aren't part of it.
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// The outcome of reading an image: codes win over text, since a code in the picture is
/// almost always the point of capturing it.
public enum CaptureResult: Equatable, Sendable {
    case codes([ScannedCode])
    case text(String)
    case nothing

    public init(lines: [RecognizedLine], codes payloads: [String]) {
        var seen: Set<String> = []
        let unique = payloads.filter { seen.insert($0.trimmingCharacters(in: .whitespacesAndNewlines)).inserted }
        let codes = unique.compactMap(ScannedCode.init(payload:))
        if !codes.isEmpty {
            self = .codes(codes)
            return
        }
        let text = CapturedText.join(lines)
        self = text.isEmpty ? .nothing : .text(text)
    }

    /// A Wi-Fi password is on the clipboard: it should be marked concealed so clipboard
    /// history, Wisp's included, doesn't keep it.
    public var isSecret: Bool {
        guard case .codes(let codes) = self else { return false }
        return codes.contains { code in
            if case .wifi(_, .some) = code { return true }
            return false
        }
    }

    public var copyText: String? {
        switch self {
        case .codes(let codes): codes.map(\.copyText).joined(separator: "\n")
        case .text(let text): text
        case .nothing: nil
        }
    }

    /// Says what was copied without repeating it.
    public var notice: String {
        switch self {
        case .codes(let codes):
            return codes.count == 1 ? codes[0].notice : "Copied \(codes.count) codes"
        case .text(let text):
            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            return words == 1 ? "Copied 1 word" : "Copied \(words) words"
        case .nothing:
            return "No text found"
        }
    }
}

/// Text taken from a PDF for the AI to summarise.
public enum PDFText {
    /// Pages tidied and joined with a blank line; empty pages dropped.
    public static func clean(pages: [String]) -> String {
        pages.map { page in
            CapturedText.clean(
                CapturedText.joiningHyphens(CapturedText.clean(page).components(separatedBy: "\n"))
                    .joined(separator: "\n"))
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    /// Which pages to read. The model only takes a few pages' worth and keeps the start and the
    /// end, so a long document is read the same way: two thirds from the start, the rest from the end.
    public static func pageIndices(count: Int, limit: Int) -> [Int] {
        guard count > limit else { return Array(0..<max(0, count)) }
        let head = limit * 2 / 3
        return Array(0..<head) + Array((count - (limit - head))..<count)
    }

    /// The longest file name the notice shows before cutting it with an ellipsis.
    public static let noticeNameLimit = 40

    /// Confirms the copy; the summary itself is on the clipboard, since a notice holds one line.
    public static func notice(fileName: String) -> String {
        let name = fileName.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let shown = name.count > noticeNameLimit ? name.prefix(noticeNameLimit - 1) + "…" : name
        return "Copied a summary of \(shown)"
    }
}
