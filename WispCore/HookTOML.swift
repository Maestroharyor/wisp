import Foundation

/// Wisp's hooks as `[[hooks]]` tables in a TOML file (Kimi Code's config.toml, Mistral Vibe's
/// hooks.toml). There's no TOML library in Wisp, so this works on lines: the user's text stays
/// exactly as written, Wisp's tables go at the end, and a `[[hooks]]` table whose `command` runs
/// the helper is Wisp's. Table headers inside multi-line strings are left alone.
public enum HookTOML {
    public enum Failure: Error {
        case notText
        /// The file sets `hooks = [...]` inline, which `[[hooks]]` tables can't be added to.
        case inlineHooks
    }

    static let header = "[[hooks]]"

    /// The file with Wisp's tables for `file`'s events (and tool events with `tools`) at the end,
    /// replacing any it had.
    static func install(into data: Data, command: String, file: HookFile, tools: Bool) throws -> Data {
        let chunks = split(try text(data))
        if chunks.first?.contains(where: { key(of: $0) == "hooks" }) == true { throw Failure.inlineHooks }
        let base = joined(chunks.map(withoutWisp))
        let tables = (file.events + (tools ? file.toolEvents : [])).map {
            table(event: $0, command: command, file: file)
        }
        return Data((base + (base.isEmpty ? "" : "\n") + tables.joined(separator: "\n")).utf8)
    }

    /// The file without Wisp's tables.
    static func remove(from data: Data) throws -> Data {
        Data(joined(split(try text(data)).map(withoutWisp)).utf8)
    }

    /// The event and command of each of Wisp's tables.
    static func commands(in data: Data) throws -> [(event: String, command: String)] {
        split(try text(data)).filter(isWisp).compactMap { lines in
            let event = lines.lazy.compactMap { line in
                ["event", "type"].contains(key(of: line)) ? value(of: line) : nil
            }.first
            let command = lines.lazy.compactMap { key(of: $0) == "command" ? value(of: $0) : nil }.first
            guard let event, let command else { return nil }
            return (event, command)
        }
    }

    /// One table. Kimi Code rejects keys it doesn't know; Vibe needs a unique `name` and a `match`
    /// (an fnmatch glob, so `*` is every tool and every agent).
    private static func table(event: String, command: String, file: HookFile) -> String {
        let fields =
            file.format == .vibeHooks
            ? [
                "name = \(quoted("wisp-" + event.replacingOccurrences(of: "_", with: "-")))",
                "type = \(quoted(event))", "match = \(quoted("*"))", "command = \(quoted(command))", "timeout = 5.0",
            ]
            : ["event = \(quoted(event))", "command = \(quoted(command))", "timeout = 5"]
        return ([header] + fields).joined(separator: "\n") + "\n"
    }

    private static func text(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.notText }
        return text
    }

    /// The lines before the first table header, then one chunk per table, each starting with its
    /// header.
    static func split(_ text: String) -> [[String]] {
        var chunks: [[String]] = [[]]
        var state = LineState()
        for line in text.components(separatedBy: "\n") {
            if state.isTopLevel, line.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                // A header opens nothing, so a malformed one can't hide every header after it.
                chunks.append([line])
            } else {
                chunks[chunks.count - 1].append(line)
                state = state.after(line)
            }
        }
        return chunks
    }

    /// What's still open at the end of a line: a `"""` or `'''` string, or arrays a value spans
    /// lines with. A line starting with `[` is a table header only when neither is.
    private struct LineState {
        var openString: String?
        var depth = 0

        var isTopLevel: Bool { openString == nil && depth == 0 }

        /// Triple quotes in a comment or inside a one-line string open nothing, an escaped quote in
        /// a `"""` string doesn't close it, and brackets inside strings or comments don't count.
        func after(_ line: String) -> LineState {
            var state = self
            var rest = Substring(line)
            while !rest.isEmpty {
                if let delimiter = state.openString {
                    guard let after = closing(delimiter, in: rest) else { return state }
                    rest = after
                    state.openString = nil
                } else if rest.hasPrefix(basicMultiline) || rest.hasPrefix(literalMultiline) {
                    state.openString = String(rest.prefix(3))
                    rest = rest.dropFirst(3)
                } else {
                    switch rest.first {
                    case "#": return state
                    case "\"": rest = afterOneLine(rest.dropFirst(), quote: "\"", escapes: true)
                    case "'": rest = afterOneLine(rest.dropFirst(), quote: "'", escapes: false)
                    case "[":
                        state.depth += 1
                        rest = rest.dropFirst()
                    case "]":
                        state.depth = max(0, state.depth - 1)
                        rest = rest.dropFirst()
                    default: rest = rest.dropFirst()
                    }
                }
            }
            return state
        }
    }

    private static let basicMultiline = "\"\"\""
    private static let literalMultiline = "'''"

    /// The text after the delimiter that closes an open multi-line string, or nil when it stays open.
    private static func closing(_ delimiter: String, in text: Substring) -> Substring? {
        var rest = text
        while !rest.isEmpty {
            if rest.hasPrefix(delimiter) { return rest.dropFirst(delimiter.count) }
            // Only basic strings have escapes; `\"""` there is a quote and two more.
            rest = delimiter == basicMultiline && rest.first == "\\" ? rest.dropFirst(2) : rest.dropFirst()
        }
        return nil
    }

    /// The text after a one-line string's closing quote; empty when the line ends first.
    private static func afterOneLine(_ text: Substring, quote: Character, escapes: Bool) -> Substring {
        var rest = text
        while let character = rest.first {
            if character == quote { return rest.dropFirst() }
            rest = escapes && character == "\\" ? rest.dropFirst(2) : rest.dropFirst()
        }
        return rest
    }

    private static func isWisp(_ chunk: [String]) -> Bool {
        guard let first = chunk.first, normalizedHeader(first) == header else { return false }
        return chunk.contains { key(of: $0) == "command" && value(of: $0)?.contains(HookInstaller.helperName) == true }
    }

    /// A chunk of Wisp's loses its table; blank and comment lines after it stay, since they may
    /// lead into the user's next table.
    private static func withoutWisp(_ chunk: [String]) -> [String] {
        guard isWisp(chunk) else { return chunk }
        guard let last = chunk.lastIndex(where: isContent) else { return [] }
        return Array(chunk[(last + 1)...])
    }

    private static func isContent(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.hasPrefix("#")
    }

    /// The lines as one text with no trailing blank lines, ending in a newline unless empty.
    private static func joined(_ chunks: [[String]]) -> String {
        var text = chunks.flatMap { $0 }.joined(separator: "\n")
        while let last = text.last, last.isWhitespace { text.removeLast() }
        return text.isEmpty ? "" : text + "\n"
    }

    /// `[[ hooks ]] # note` as `[[hooks]]`.
    private static func normalizedHeader(_ line: String) -> String {
        let body = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return body.filter { !$0.isWhitespace }
    }

    /// The bare key of a `key = value` line; nil for anything else.
    static func key(of line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return key
    }

    /// A basic (`"..."`) or literal (`'...'`) string value of a `key = value` line; nil for any
    /// other value.
    static func value(of line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let rest = line[line.index(after: equals)...].drop(while: { $0 == " " || $0 == "\t" })
        guard let quote = rest.first else { return nil }
        let body = rest.dropFirst()
        if quote == "'" {
            guard let end = body.firstIndex(of: "'") else { return nil }
            return String(body[..<end])
        }
        guard quote == "\"" else { return nil }
        return basicString(body)
    }

    /// A basic string's content up to its closing quote, with escapes read.
    private static func basicString(_ body: Substring) -> String? {
        var result = ""
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            index = body.index(after: index)
            if character == "\"" { return result }
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard index < body.endIndex else { return nil }
            let escape = body[index]
            index = body.index(after: index)
            switch escape {
            case "b": result.append("\u{08}")
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "f": result.append("\u{0C}")
            case "r": result.append("\r")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "u", "U":
                let count = escape == "u" ? 4 : 8
                guard let end = body.index(index, offsetBy: count, limitedBy: body.endIndex),
                    let code = UInt32(body[index..<end], radix: 16), let scalar = Unicode.Scalar(code)
                else { return nil }
                result.unicodeScalars.append(scalar)
                index = end
            default: return nil
            }
        }
        return nil
    }

    /// `text` as a TOML basic string.
    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
