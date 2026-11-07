import Foundation
import WispCore

/// "Always allow" rules, saved in Claude Code's own `permissions.allow` rather than kept by
/// Wisp: the user and the agent can see them, and they hold when Wisp isn't running. Wisp's
/// hook never approves anything on a rule's behalf.
extension AgentHub {
    /// A rules file for Settings: the user's settings, or a project's local settings.
    struct RulesFile: Identifiable, Equatable {
        var id: String { path }
        let title: String
        let path: String
        let scope: RuleScope
        let lists: PermissionRulesFile.Lists
        /// Set when the file couldn't be read, so its rules aren't listed.
        let problem: String?

        var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
    }

    enum RulesError: Error {
        case noProject
    }

    /// Whether Wisp writes this agent's rules: only agents whose rule format Wisp knows
    /// (Claude Code's `permissions.allow` for now).
    static func writesRules(_ source: AgentSource) -> Bool { source.adapter.capabilities.contains(.rules) }

    /// Rules for a tool request's card; plans and questions never get them.
    static func suggestedRules(_ event: AgentEvent) -> [String] {
        guard writesRules(event.source), event.prompt == .tool, let tool = event.toolName else { return [] }
        return PermissionRule.suggest(tool: tool, input: event.rawToolInput, cwd: event.cwd)
    }

    /// The settings file for `scope`; nil for a project whose folder isn't known.
    static func rulesPath(_ scope: RuleScope, cwd: String) -> String? {
        PermissionRulesFile.path(
            for: scope, cwd: cwd, home: FileManager.default.homeDirectoryForCurrentUser.path,
            read: { try? String(contentsOfFile: $0, encoding: .utf8) })
    }

    /// Saves the rules, then allows the request through the usual answer. Throws, leaving the
    /// request waiting, when the file can't be read or written.
    func alwaysAllow(_ approval: AgentApproval, rules: [String], scope: RuleScope) throws {
        guard !rules.isEmpty else { return }
        guard let path = Self.rulesPath(scope, cwd: approval.cwd) else { throw RulesError.noProject }
        let url = URL(fileURLWithPath: path)
        let original = try Self.existing(url)
        if !Set(rules).isSubset(of: try PermissionRulesFile.lists(in: original).allow) {
            try Self.save(try PermissionRulesFile.adding(rules, to: original), to: url, scope: scope)
        }
        answer(approval.id, allow: true)
        let saved = rules.count == 1 ? rules[0] : "\(rules.count) rules"
        onNotice(detailsHidden ? "Saved an always-allow rule" : "Always allowing \(saved)")
    }

    /// Takes a rule out of a file's `permissions.allow`.
    func removeRule(_ rule: String, from file: RulesFile) throws {
        let url = URL(fileURLWithPath: file.path)
        try Self.save(try PermissionRulesFile.removing(rule, from: try Self.existing(url)), to: url, scope: file.scope)
    }

    /// User settings keep Wisp's copies beside them; a project's local file is replaced
    /// without any, so nothing extra lands in the repository.
    private static func save(_ data: Data, to url: URL, scope: RuleScope) throws {
        if scope.keepsCopies {
            try SettingsFileWriter.backUpOnce(url)
            try SettingsFileWriter.write(data, to: url)
        } else {
            try SettingsFileWriter.replace(data, at: url)
        }
    }

    /// The user's settings, then each Claude Code project with a live session.
    func rulesFiles() -> [RulesFile] {
        var files: [(title: String, path: String, scope: RuleScope)] = []
        if let everywhere = Self.rulesPath(.everywhere, cwd: "") {
            files.append(("Everywhere", everywhere, .everywhere))
        }
        for session in sessions.list where Self.writesRules(session.source) {
            guard let path = Self.rulesPath(.project, cwd: session.cwd), !files.contains(where: { $0.path == path })
            else { continue }
            files.append((session.project, path, .project))
        }
        return files.map { file in
            do {
                let lists = try PermissionRulesFile.lists(in: try Self.existing(URL(fileURLWithPath: file.path)))
                return RulesFile(title: file.title, path: file.path, scope: file.scope, lists: lists, problem: nil)
            } catch {
                return RulesFile(
                    title: file.title, path: file.path, scope: file.scope, lists: PermissionRulesFile.Lists(),
                    problem: Self.rulesProblem(error, path: file.path))
            }
        }
    }

    /// What went wrong, as UI copy.
    static func rulesProblem(_ error: Error, path: String) -> String {
        let shown = (path as NSString).abbreviatingWithTildeInPath
        switch error {
        case RulesError.noProject:
            return "Wisp doesn't know this session's folder. Choose Everywhere instead."
        case is PermissionRulesFile.Failure, is DecodingError:
            return "Couldn't read \(shown). Fix the file's JSON, then try again."
        default:
            return "Couldn't write \(shown): \(error.localizedDescription)"
        }
    }

    /// A missing file reads as empty; one that exists but can't be read throws, so it's never
    /// replaced by a file holding only Wisp's rule.
    private static func existing(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { return Data() }
        return try Data(contentsOf: url)
    }
}
