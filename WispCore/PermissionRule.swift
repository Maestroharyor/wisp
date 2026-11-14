import Foundation

/// Suggests a Claude Code permission rule that would allow a tool call without asking again,
/// for "Always allow…" on an approval card. Suggestions stay close to the call: a prefix
/// rule only past a real subcommand, otherwise the exact command, and never a bare tool.
///
/// Syntax from Claude Code's permissions docs (code.claude.com/docs/en/permissions, read for
/// 2.1.319): `Bash(git commit *)` matches the words before the `*` (the dialog writes this
/// space form; `:*` is equivalent), and compound commands are split on `&&`, `||`, `;`, `|`,
/// `|&`, `&` and newlines, every part needing its own rule. `Edit` and `Read` take gitignore
/// patterns: `src/**` from the session's folder, `//path` absolute. `Write` and `NotebookEdit`
/// are covered by `Edit` rules. `WebFetch(domain:host)` and `mcp__server__tool` by name.
public enum PermissionRule {
    /// Claude Code saves at most five rules for one compound command; Wisp does the same.
    static let maximumRules = 5

    /// The rules that would cover this call, or none when Wisp can't suggest a safe one.
    public static func suggest(tool: String, input: JSONValue?, cwd: String) -> [String] {
        switch tool {
        case "Bash":
            return input?["command"]?.stringValue.map(bash) ?? []
        case "Edit", "Write", "MultiEdit":
            return file(input?["file_path"]?.stringValue, rule: "Edit", cwd: cwd)
        case "NotebookEdit":
            return file(input?["notebook_path"]?.stringValue, rule: "Edit", cwd: cwd)
        case "Read":
            return file(input?["file_path"]?.stringValue, rule: "Read", cwd: cwd)
        case "WebFetch":
            return domain(input?["url"]?.stringValue)
        default:
            return isMCPTool(tool) ? [tool] : []
        }
    }

    // MARK: Editing

    /// One rule per non-empty line of the sheet's text.
    public static func rules(in text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty
        }
    }

    /// Why the edited rules can't be saved, as UI copy; nil when they can.
    public static func problem(in rules: [String]) -> String? {
        if rules.isEmpty { return "Add a rule." }
        for rule in rules {
            if !isWellFormed(rule) { return "\u{201C}\(rule)\u{201D} isn't a rule. Write Tool(pattern)." }
            if isTooBroad(rule) {
                return "\u{201C}\(rule)\u{201D} allows every call. Add a pattern, such as Bash(npm test *)."
            }
        }
        return nil
    }

    /// A whole tool, a whole MCP server or a match-everything pattern.
    static func isTooBroad(_ rule: String) -> Bool {
        guard let open = rule.firstIndex(of: "(") else {
            return rule.contains("*") || !isMCPTool(rule)
        }
        guard rule.hasSuffix(")"), rule.index(after: open) < rule.endIndex else { return false }
        let content = rule[rule.index(after: open)..<rule.index(before: rule.endIndex)]
        return everything.contains(content.trimmingCharacters(in: .whitespaces))
    }

    private static let everything: Set<String> = ["*", "**", "/**", "//**", "./**", "~/**", "domain:*"]

    /// `Tool` or `Tool(pattern)`.
    static func isWellFormed(_ rule: String) -> Bool {
        let name = rule.prefix { $0 != "(" }
        guard let first = name.first, first.isLetter || first == "_",
            name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-*".contains($0)) })
        else { return false }
        if name.count == rule.count { return true }
        return rule.hasSuffix(")") && rule.count > name.count + 2
    }

    /// Rules for user settings, which apply in every project: a project-relative `Edit` or
    /// `Read` pattern is anchored to the session's folder (`//abs/folder/src/**`), since left
    /// relative it would match that folder in every project.
    public static func anchored(_ rules: [String], cwd: String) -> [String] {
        guard cwd.hasPrefix("/") else { return rules }
        let root = URL(fileURLWithPath: cwd).standardized.path
        return rules.map { rule in
            for tool in ["Edit", "Read"] {
                let open = tool + "("
                guard rule.hasPrefix(open), rule.hasSuffix(")") else { continue }
                let pattern = String(rule.dropFirst(open.count).dropLast())
                guard !pattern.isEmpty, !"/~!".contains(pattern[pattern.startIndex]) else { return rule }
                let relative = pattern.hasPrefix("./") ? String(pattern.dropFirst(2)) : pattern
                let base = root == "/" ? "" : escaped(root)
                return "\(tool)(/\(base)/\(relative))"
            }
            return rule
        }
    }

    // MARK: Bash

    private struct Word {
        /// The word as the shell sees it, quotes removed.
        var text = ""
        /// The word as written.
        var raw = ""
        var quoted = false
    }

    private struct Part {
        var words: [Word] = []
        var redirects = false
    }

    private enum Outcome: Equatable {
        case skip
        case rule(String)
        /// No safe rule, so nothing can cover the whole call.
        case none
    }

    static func bash(_ command: String) -> [String] {
        guard let parts = parts(command), parts.count <= maximumRules else { return [] }
        var rules: [String] = []
        for part in parts {
            switch rule(for: part) {
            case .skip: continue
            case .none: return []
            case .rule(let rule): if !rules.contains(rule) { rules.append(rule) }
            }
        }
        return rules
    }

    /// Words a rule never widens past, because they run other commands, delete or move files,
    /// reach the network or change permissions. Every shell is one of them.
    private static let exactOnly: Set<String> = ShellNames.all.union([
        "rm", "rmdir", "unlink", "shred", "dd", "mkfs", "sudo", "su", "doas", "eval", "exec", "source", "env",
        "xargs", "chmod", "chown", "chgrp", "kill", "killall", "pkill", "mv", "cp", "ln", "curl", "wget", "ssh",
        "scp", "sftp", "rsync", "open", "osascript", "python", "python3", "node", "ruby", "perl", "php", "deno",
        "lua", "npx", "bunx", "pnpx", "uvx", "docker", "podman", "kubectl", "find", "watch", "setsid", "ionice",
        "flock", "timeout", "nice", "stdbuf", "direnv", "devbox", "mise", "asdf", "nix", "launchctl", "crontab",
        "security", "defaults",
    ])

    /// Second words that run whatever follows them (`cargo run`, `npm exec`).
    private static let runners: Set<String> = ["run", "exec", "x", "dlx", "eval", "shell", "sh"]

    /// Second words that push, rewrite history, publish or delete. One approval of these
    /// never becomes a prefix rule, since `git push *` would also allow `git push --force`.
    private static let destructive: Set<String> = [
        "push", "reset", "clean", "rebase", "checkout", "restore", "rm", "branch", "tag", "stash", "merge",
        "filter-branch", "filter-repo", "update-ref", "publish", "unpublish", "deploy", "delete", "destroy", "drop",
        "prune", "uninstall", "remove", "purge", "wipe",
    ]

    /// Their `run` takes a script name from the project's manifest, kept in the rule.
    private static let packageManagers: Set<String> = ["npm", "pnpm", "yarn", "bun"]

    /// Wrappers Claude Code strips before matching that take no arguments of their own.
    private static let wrappers: Set<String> = ["time", "nohup", "noglob", "builtin"]

    private static let keywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "function",
        "select", "in", "{", "}", "[[", "]]", "!",
    ]

    private static func rule(for part: Part) -> Outcome {
        var words = part.words
        while let first = words.first, !first.quoted, isStrippedWrapper(first.text, next: words.dropFirst().first) {
            words.removeFirst()
        }
        guard let first = words.first else { return .none }
        if !first.quoted, keywords.contains(first.text) { return .none }
        // `cd` within the project needs no approval, and a rule for it would cover nothing.
        if !first.quoted, first.text == "cd" { return .skip }

        let exact = words.map(\.raw).joined(separator: " ")
        // A `*` in an exact rule is read as a wildcard, which would match more than this call.
        let fallback: Outcome = exact.contains("*") ? .none : .rule("Bash(\(exact))")
        guard !part.redirects, !isAssignment(first.raw), !first.quoted, isProgram(first.text),
            !exactOnly.contains(first.text), words.count > 1
        else { return fallback }
        let second = words[1]
        guard !second.quoted, isSubcommand(second.text) else { return fallback }
        if packageManagers.contains(first.text), second.text == "run" {
            guard words.count > 2, !words[2].quoted, isScript(words[2].text) else { return fallback }
            return .rule("Bash(\(first.text) run \(words[2].text) *)")
        }
        if runners.contains(second.text) || destructive.contains(second.text) { return fallback }
        return .rule("Bash(\(first.text) \(second.text) *)")
    }

    private static func isStrippedWrapper(_ word: String, next: Word?) -> Bool {
        if wrappers.contains(word) { return true }
        // `command -v` and `xargs -n1` aren't stripped, so their rules keep them.
        guard word == "command" || word == "xargs", let next else { return false }
        return !next.raw.hasPrefix("-")
    }

    private static func isAssignment(_ raw: String) -> Bool {
        guard let equals = raw.firstIndex(of: "=") else { return false }
        let name = raw[..<equals]
        return !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    private static func isProgram(_ word: String) -> Bool {
        guard let first = word.first, first.isASCII, first.isLetter || first.isNumber || first == "_" else {
            return false
        }
        return word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._+-".contains($0)) }
    }

    private static func isSubcommand(_ word: String) -> Bool {
        guard let first = word.first, first.isASCII, first.isLowercase else { return false }
        return word.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || "_:-".contains($0)) }
    }

    private static func isScript(_ word: String) -> Bool {
        guard let first = word.first, first.isASCII, first.isLetter || first.isNumber || first == "_" else {
            return false
        }
        return word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_:.-".contains($0)) }
    }

    /// Splits a command into its parts the way Claude Code's separators do. Nil for anything
    /// Wisp can't read with confidence: substitutions, subshells, heredocs, comments,
    /// unclosed quotes and separators with nothing after them.
    private static func parts(_ command: String) -> [Part]? {
        let chars = Array(command)
        var parts: [Part] = []
        var part = Part()
        var word = Word()
        var inWord = false
        var needsMore = false
        var index = 0

        func endWord() {
            if inWord { part.words.append(word) }
            word = Word()
            inWord = false
        }
        func add(_ text: String, plain: String, quoted: Bool = false) {
            word.raw += text
            word.text += plain
            word.quoted = word.quoted || quoted
            inWord = true
        }
        /// False when the separator has nothing before it.
        func endPart(requiringMore: Bool) -> Bool {
            endWord()
            if part.words.isEmpty {
                if needsMore || requiringMore { return false }
            } else {
                parts.append(part)
            }
            part = Part()
            needsMore = requiringMore
            return true
        }

        while index < chars.count {
            let char = chars[index]
            let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            switch char {
            case "\\":
                guard let next else { return nil }
                if next == "\n" {
                    endWord()
                } else {
                    add(String([char, next]), plain: String(next), quoted: true)
                }
                index += 2
                continue
            case "'":
                guard let end = chars[(index + 1)...].firstIndex(of: "'") else { return nil }
                add(String(chars[index...end]), plain: String(chars[(index + 1)..<end]), quoted: true)
                index = end + 1
                continue
            case "\"":
                guard let end = closingQuote(chars, from: index + 1) else { return nil }
                add(String(chars[index...end]), plain: String(chars[(index + 1)..<end]), quoted: true)
                index = end + 1
                continue
            case "`", "(", ")":
                return nil
            case "$" where next == "(":
                return nil
            case "#" where !inWord:
                return nil
            case "<" where next == "<":
                return nil
            case "<", ">":
                part.redirects = true
                // `2>&1` and `>&2` are redirects, not a background `&`.
                if next == "&" {
                    add(String([char, "&"]), plain: String([char, "&"]))
                    index += 2
                    continue
                }
                add(String(char), plain: String(char))
            case "&" where next == ">":
                part.redirects = true
                add("&>", plain: "&>")
                index += 2
                continue
            case "&", "|":
                let double = next == char || (char == "|" && next == "&")
                // A lone `&` or `;` may end a command; `&&`, `||` and pipes need something after.
                guard endPart(requiringMore: double || char == "|") else { return nil }
                index += double ? 2 : 1
                continue
            case ";", "\n":
                guard endPart(requiringMore: false) else { return nil }
            case " ", "\t":
                endWord()
            default:
                add(String(char), plain: String(char))
            }
            index += 1
        }
        guard endPart(requiringMore: false) else { return nil }
        return needsMore ? nil : parts
    }

    /// The closing `"` from `start`, past escaped characters. Nil when there's none, or when
    /// the string substitutes a command.
    private static func closingQuote(_ chars: [Character], from start: Int) -> Int? {
        var index = start
        while index < chars.count {
            switch chars[index] {
            case "\\": index += 2
            case "\"": return index
            case "`": return nil
            case "$" where index + 1 < chars.count && chars[index + 1] == "(": return nil
            default: index += 1
            }
        }
        return nil
    }

    // MARK: Files, domains and MCP tools

    /// A file in a folder of the project allows that folder; one at the project's top or
    /// outside it is matched exactly, since its folder could be the home folder or `/`.
    private static func file(_ path: String?, rule: String, cwd: String) -> [String] {
        guard let path, !path.isEmpty else { return [] }
        let hasRoot = cwd.hasPrefix("/")
        guard path.hasPrefix("/") || hasRoot else { return [] }
        let absolute = path.hasPrefix("/") ? path : (cwd as NSString).appendingPathComponent(path)
        let file = URL(fileURLWithPath: absolute).standardized.path
        if hasRoot {
            let root = URL(fileURLWithPath: cwd).standardized.path
            if root != "/", file.hasPrefix(root + "/") {
                let folder = (String(file.dropFirst(root.count + 1)) as NSString).deletingLastPathComponent
                if !folder.isEmpty { return ["\(rule)(\(escaped(folder))/**)"] }
            }
        }
        return ["\(rule)(/\(escaped(file)))"]
    }

    /// Gitignore pattern characters in a real path, escaped so the rule matches it literally.
    private static func escaped(_ path: String) -> String {
        var result = ""
        for (offset, char) in path.enumerated() {
            if "*?[]\\".contains(char) || (offset == 0 && "!#".contains(char)) { result.append("\\") }
            result.append(char)
        }
        return result
    }

    private static func domain(_ url: String?) -> [String] {
        guard let host = url.flatMap(URL.init(string:))?.host?.lowercased() else { return [] }
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !name.isEmpty, !name.contains("*") else { return [] }
        return ["WebFetch(domain:\(name))"]
    }

    /// `mcp__server__tool`: one tool from one server.
    private static func isMCPTool(_ name: String) -> Bool {
        guard name.hasPrefix("mcp__"), !name.contains("*"), !name.contains("(") else { return false }
        let rest = name.dropFirst(5)
        guard let separator = rest.range(of: "__") else { return false }
        return separator.lowerBound > rest.startIndex && separator.upperBound < rest.endIndex
    }
}
