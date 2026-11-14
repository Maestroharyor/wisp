import Foundation

/// The "Always allow" choices for a request, narrowest first, and how many recent requests
/// each would have covered.
///
/// A single shell command gets its exact rule and then shorter word prefixes, down to the
/// prefix `PermissionRule` would suggest (`git log --oneline *`, `git log *`). It never goes
/// down to the program alone (`git *`), and commands `PermissionRule` keeps exact (pushes,
/// deletes, runners) stay exact. Compound commands and ones with substitutions get no choices;
/// the editable "Always allow…" sheet still covers them. Other tools offer the one rule
/// `PermissionRule` suggests.
public enum RuleSuggestion {
    public static let maximumChoices = 4
    /// Recent tool requests a choice is measured against.
    public static let window = 50

    /// Each choice is the rules it would save; most hold one.
    public static func choices(tool: String, input: JSONValue?, cwd: String) -> [[String]] {
        guard tool == "Bash" else {
            let rules = PermissionRule.suggest(tool: tool, input: input, cwd: cwd)
            return rules.isEmpty ? [] : [rules]
        }
        guard let command = input?["command"]?.stringValue else { return [] }
        return bash(command).map { [$0] }
    }

    static func bash(_ command: String) -> [String] {
        guard let parts = PermissionRule.parts(command), parts.count == 1, let part = parts.first,
            case .rule(let base) = PermissionRule.rule(for: part)
        else { return [] }
        let words = PermissionRule.strippedWords(part)
        let exact = "Bash(" + words.map(\.raw).joined(separator: " ") + ")"
        guard base.hasSuffix(" *)") else { return [base] }
        // How many words the suggested prefix keeps ("git log" is 2, "npm run build" is 3).
        let baseCount = base.dropFirst("Bash(".count).dropLast(" *)".count).split(separator: " ").count
        var prefixes: [String] = []
        if words.count > baseCount {
            for count in stride(from: words.count - 1, to: baseCount, by: -1) {
                // A quoted or wildcard word would make the prefix mean something else.
                guard words[baseCount..<count].allSatisfy({ !$0.quoted && !$0.raw.contains("*") }) else { continue }
                prefixes.append("Bash(" + words.prefix(count).map(\.raw).joined(separator: " ") + " *)")
            }
        }
        var all = (exact.contains("*") || exact == base ? [] : [exact]) + prefixes + [base]
        if all.count > maximumChoices {
            all = Array(all.prefix(maximumChoices - 1)) + [base]
        }
        return all
    }

    /// How many of `records` any of `rules` would have allowed. Records saved while details
    /// were hidden have no summary and never count.
    public static func matchCount(_ rules: [String], in records: [ApprovalRecord]) -> Int {
        records.filter { record in
            guard let summary = record.summary else { return false }
            return rules.contains { PermissionRule.matches($0, tool: record.tool, summary: summary) }
        }.count
    }

    /// "Matches 3 of your last 50 requests"; nil before any request was recorded.
    public static func matchText(count: Int, of total: Int) -> String? {
        guard total > 0 else { return nil }
        return total == 1
            ? "Matches \(count) of your last request" : "Matches \(count) of your last \(total) requests"
    }
}

extension PermissionRule {
    /// Whether `rule` covers a request for `tool` whose card summary was `summary` (the command,
    /// file path or URL). Follows Claude Code's matching closely enough for counting: a Bash
    /// prefix matches whole words and every part of a compound command (a `cd` aside), file
    /// rules match `//absolute` paths and `folder/**` anywhere under that folder name.
    public static func matches(_ rule: String, tool: String, summary: String) -> Bool {
        let name = String(rule.prefix { $0 != "(" })
        let content: String? =
            name.count == rule.count
            ? nil : rule.hasSuffix(")") ? String(rule.dropFirst(name.count + 1).dropLast()) : nil
        if name.count != rule.count, content == nil { return false }
        switch name {
        case "Bash":
            guard tool == "Bash" else { return false }
            guard let content else { return true }
            return bashMatches(content, command: summary)
        case "Edit":
            guard ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(tool) else { return false }
            return content.map { fileMatches($0, path: summary) } ?? true
        case "Read":
            guard tool == "Read" else { return false }
            return content.map { fileMatches($0, path: summary) } ?? true
        case "WebFetch":
            guard tool == "WebFetch" else { return false }
            guard let content else { return true }
            guard content.hasPrefix("domain:"), let host = URL(string: summary)?.host?.lowercased() else {
                return false
            }
            return host == content.dropFirst("domain:".count).lowercased()
        default:
            return content == nil && name == tool
        }
    }

    private static func bashMatches(_ pattern: String, command: String) -> Bool {
        let prefix: String? =
            pattern.hasSuffix(" *") || pattern.hasSuffix(":*") ? String(pattern.dropLast(2)) : nil
        guard let parts = parts(command) else {
            // Something Wisp can't split: only an exact rule can be sure of it.
            return prefix == nil && command == pattern
        }
        let commands = parts.map { strippedWords($0) }.filter { words in
            !(words.first.map { !$0.quoted && $0.text == "cd" } ?? false)
        }
        guard !commands.isEmpty else { return false }
        return commands.allSatisfy { words in
            let text = words.map(\.raw).joined(separator: " ")
            guard let prefix else { return text == pattern }
            return text == prefix || text.hasPrefix(prefix + " ")
        }
    }

    private static func fileMatches(_ pattern: String, path: String) -> Bool {
        let plain = pattern.replacingOccurrences(of: "\\", with: "")
        let folder = plain.hasSuffix("/**") ? String(plain.dropLast(3)) : nil
        if plain.hasPrefix("//") {
            let absolute = String(plain.dropFirst())
            guard let folder else { return path == absolute }
            return path.hasPrefix(String(folder.dropFirst()) + "/")
        }
        // Relative to a project Wisp doesn't keep, so any folder of that name counts.
        guard !plain.hasPrefix("/"), !plain.hasPrefix("~"), let folder else { return false }
        let relative = folder.hasPrefix("./") ? String(folder.dropFirst(2)) : folder
        return path.contains("/" + relative + "/")
    }
}
