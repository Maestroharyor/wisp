import Foundation

/// A tool call in a few words, for the details ("Running npm test", "Editing Hub.swift"),
/// and shorter for the notch pill, where an SF Symbol stands in for the verb.
public struct ToolDescription: Equatable, Sendable {
    public let symbol: String
    /// The whole phrase, at most `ToolLabel.limit` characters.
    public let label: String
    /// The pill's text: the subject ("npm test"), or the verb alone when hidden ("Running").
    public let short: String
}

/// Turns a tool call into a `ToolDescription`. Commands are masked first, so tokens and
/// passwords typed into them don't show.
public enum ToolLabel {
    /// Characters a label may take, "…" included.
    public static let limit = 32
    /// The pill truncates in the middle as it fits; this only caps runaway commands.
    static let shortLimit = 60
    static let mask = "•••"

    /// `hidden` (private mode) keeps only the verb and the kind of thing, never the input.
    public static func label(tool: String?, input: ToolInput, hidden: Bool) -> String {
        describe(tool: tool, input: input, hidden: hidden).label
    }

    public static func describe(tool: String?, input: ToolInput, hidden: Bool) -> ToolDescription {
        let name = tool ?? "Tool"
        let symbol: String
        // `verb` is empty when the subject says it all.
        let verb: String
        let subject: String
        switch name {
        case "Bash":
            (symbol, verb) = ("terminal", "Running")
            subject = hidden ? "a command" : firstLine(mask(input.command ?? ""))
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            (symbol, verb) = ("pencil", "Editing")
            subject = hidden ? "a file" : fileName(input.filePath ?? input.notebookPath)
        case "Read":
            (symbol, verb) = ("doc.text", "Reading")
            subject = hidden ? "a file" : fileName(input.filePath)
        case "Grep", "Glob":
            (symbol, verb) = ("magnifyingglass", "Searching")
            subject = hidden ? "files" : firstLine(mask(input.pattern ?? ""))
        case "WebFetch":
            (symbol, verb) = ("globe", "Fetching")
            subject = hidden ? "a page" : input.url.flatMap { URL(string: $0)?.host } ?? "a page"
        case "WebSearch":
            (symbol, verb, subject) = ("globe", "", "Searching the web")
        case "Task", "Agent":
            symbol = "person.2"
            let kind = input.subagentType ?? input.description.map { firstLine(mask($0)) }
            if let kind, !hidden {
                (verb, subject) = ("Subagent:", kind)
            } else {
                (verb, subject) = ("Running", "a subagent")
            }
        default:
            // MCP tools are named mcp__<server>__<tool>; neither part is the user's data.
            let parts = name.components(separatedBy: "__")
            let mcp = parts.count >= 3 && parts[0] == "mcp"
            symbol = mcp ? "puzzlepiece.extension" : "wrench.and.screwdriver"
            verb = ""
            subject = mcp ? "\(parts[1]): \(parts[2...].joined(separator: "__"))" : name
        }
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        let label = verb.isEmpty ? trimmed : trimmed.isEmpty ? verb : "\(verb) \(trimmed)"
        let short = hidden && !verb.isEmpty ? verb : trimmed.isEmpty ? verb : trimmed
        return ToolDescription(symbol: symbol, label: cut(label, to: limit), short: cut(short, to: shortLimit))
    }

    /// `text` with likely secrets replaced by "•••". Pattern-based, so it can miss some;
    /// private mode is the full guarantee.
    public static func mask(_ text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
    }

    private static let secretName = "[A-Za-z0-9_]*(?:TOKEN|KEY|SECRET|PASSWORD|PASSWD|PASS|AUTH)[A-Za-z0-9_]*"
    private static let value = #"(?:"[^"]*"|'[^']*'|[^\s'"&]+)"#

    // Order matters: the specific rules run before the catch-all ones, and each leaves
    // "•••" behind, which no later rule matches.
    private static let rules: [Rule] = [
        // GITHUB_TOKEN=abc, export API_KEY='x'
        rule(#"\b(\#(secretName)=)\#(value)"#, "$1\(mask)", caseInsensitive: true),
        // --password x, --token=x, --api-key x
        rule(
            #"(--(?:password|passwd|token|api-key|apikey|secret|auth-token|access-token)[= ])\#(value)"#,
            "$1\(mask)", caseInsensitive: true),
        // mysql -phunter2 (the password is attached to -p; `mkdir -p dir` has a space)
        rule(#"(\b(?:mysql|mysqldump|mariadb)\b.*?\s-p)(?=[^\s-])\S+"#, "$1\(mask)", caseInsensitive: false),
        // Authorization: Bearer x, Authorization: token x, Bearer x
        rule(#"(authorization:\s*(?:bearer|basic|token)\s+)[^\s'"]+"#, "$1\(mask)", caseInsensitive: true),
        rule(#"\b(bearer\s+)(?!•)[^\s'"]+"#, "$1\(mask)", caseInsensitive: true),
        // https://user:password@host
        rule(#"(://)[^/\s:@]+:[^/\s@]+@"#, "$1\(mask)@", caseInsensitive: false),
        // ?token=x&...
        rule(
            ##"([?&](?:token|access_token|key|api_key|apikey|secret|password|sig|signature|auth)=)[^&\s'"#]+"##,
            "$1\(mask)", caseInsensitive: true),
        // Well-known key formats.
        rule(
            #"\b(?:sk-ant-|sk-|ghp_|gho_|ghu_|ghs_|github_pat_|xox[abprs]-|glpat-)[A-Za-z0-9_\-]{8,}"#, mask,
            caseInsensitive: false),
        rule(#"\bAKIA[0-9A-Z]{16}\b"#, mask, caseInsensitive: false),
        // Long blobs with letters and digits (base64, hex): not paths, which have slashes.
        rule(
            #"(?<![/\w.\-])(?=[A-Za-z0-9+_\-]*[0-9])(?=[A-Za-z0-9+_\-]*[A-Za-z])[A-Za-z0-9+_\-]{40,}={0,2}(?![/\w.])"#,
            mask, caseInsensitive: false),
    ]

    private static func rule(_ pattern: String, _ template: String, caseInsensitive: Bool) -> Rule {
        // The patterns are fixed and covered by tests, so a failure here is a programming error.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        else { preconditionFailure("bad ToolLabel pattern: \(pattern)") }
        return Rule(regex: regex, template: template)
    }

    private static func firstLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    }

    private static func fileName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "a file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func cut(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
