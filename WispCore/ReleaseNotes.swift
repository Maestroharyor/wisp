import Foundation

/// The notes in Sparkle's update window, built from each merged pull request's "Release note"
/// line (written for people who use Wisp) rather than from the developer changelog.
public enum ReleaseNotes {
    public enum Section: Int, CaseIterable, Sendable {
        case new, improved, fixed

        var title: String {
            switch self {
            case .new: "New"
            case .improved: "Improved"
            case .fixed: "Fixed"
            }
        }
    }

    /// One user-facing line for a merged pull request.
    public struct Entry: Equatable, Sendable {
        public let section: Section
        public let text: String

        /// Nil for internal changes: a type other than feat, fix or perf, or a note of "None".
        public init?(title: String, body: String) {
            guard let parsed = Title(title), let section = parsed.section else { return nil }
            switch ReleaseNotes.field(fromBody: body) {
            case .none: return nil
            case .text(let note): text = note
            case .missing: text = ReleaseNotes.sentence(parsed.subject)
            }
            self.section = section
        }
    }

    /// The pull request's release note, or nil when it's missing, empty or "None".
    public static func note(fromBody body: String) -> String? {
        if case .text(let note) = field(fromBody: body) { return note }
        return nil
    }

    /// A small HTML page in the system font that follows light and dark mode.
    public static func html(version: String, entries: [Entry], notesURL: String) -> String {
        var sections = ""
        for section in Section.allCases {
            let items = entries.filter { $0.section == section }
            guard !items.isEmpty else { continue }
            sections += "<h2>\(section.title)</h2>\n<ul>\n"
            sections += items.map { "<li>\(inline($0.text))</li>\n" }.joined()
            sections += "</ul>\n"
        }
        if sections.isEmpty { sections = "<p>Small fixes and improvements.</p>\n" }
        return """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><style>
            :root { color-scheme: light dark; }
            body { font: 13px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; margin: 14px 18px; }
            h1 { font-size: 15px; font-weight: 600; margin: 0 0 10px; }
            h2 { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em;
                 color: #8e8e93; margin: 16px 0 6px; }
            ul { margin: 0; padding-left: 18px; }
            li { margin: 0 0 6px; }
            code { font: 12px ui-monospace, Menlo, monospace; padding: 1px 4px; border-radius: 4px;
                   background: rgba(127, 127, 127, 0.15); }
            a { color: #7A6BFF; text-decoration: none; }
            .more { margin-top: 18px; font-size: 12px; }
            </style></head><body>
            <h1>What’s new in Wisp \(escape(version))</h1>
            \(sections)<p class="more"><a href="\(escape(notesURL))">Full release notes on GitHub ›</a></p>
            </body></html>

            """
    }

    // MARK: - Parsing

    enum Field: Equatable {
        case missing
        case none
        case text(String)
    }

    /// The text under "## Release note", up to the next heading, with comments removed.
    static func field(fromBody body: String) -> Field {
        var lines: [Substring] = []
        var inSection = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("##\t") {
                if inSection { break }
                inSection = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces).lowercased()
                    .hasPrefix("release note")
                continue
            }
            if inSection { lines.append(line) }
        }
        let text = withoutComments(lines.joined(separator: "\n"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.isEmpty { return .missing }
        let bare = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return bare == "none" ? .none : .text(text)
    }

    private static func withoutComments(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<!--") {
            let end = result.range(of: "-->", range: start.upperBound..<result.endIndex)?.upperBound ?? result.endIndex
            result.removeSubrange(start.lowerBound..<end)
        }
        return result
    }

    /// A conventional commit title: `type(scope)!: subject (#123)`.
    struct Title {
        let type: String
        let subject: String

        init?(_ title: String) {
            guard let colon = title.firstIndex(of: ":") else { return nil }
            var head = title[..<colon]
            if head.hasSuffix("!") { head = head.dropLast() }
            if let paren = head.firstIndex(of: "(") { head = head[..<paren] }
            guard !head.isEmpty, head.allSatisfy(\.isLetter) else { return nil }
            type = head.lowercased()
            var rest = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let suffix = rest.range(of: #"\s*\(#\d+\)$"#, options: .regularExpression) {
                rest.removeSubrange(suffix)
            }
            subject = rest
        }

        var section: Section? {
            switch type {
            case "feat": .new
            case "fix": .fixed
            case "perf": .improved
            default: nil
            }
        }
    }

    /// "permission flow" becomes "Permission flow."
    static func sentence(_ subject: String) -> String {
        guard let first = subject.first else { return subject }
        let capitalised = first.uppercased() + subject.dropFirst()
        return capitalised.last.map { ".!?".contains($0) } == true ? capitalised : capitalised + "."
    }

    // MARK: - HTML

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Escaped text with `code` spans; an unpaired backtick stays as it is.
    static func inline(_ text: String) -> String {
        let parts = escape(text).components(separatedBy: "`")
        var result = parts[0]
        var index = 1
        while index < parts.count {
            if index + 1 < parts.count {
                result += "<code>\(parts[index])</code>" + parts[index + 1]
                index += 2
            } else {
                result += "`" + parts[index]
                index += 1
            }
        }
        return result
    }
}
