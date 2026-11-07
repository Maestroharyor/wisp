import Foundation

/// Where an "Always allow" rule is saved.
public enum RuleScope: String, CaseIterable, Sendable {
    /// The project's `.claude/settings.local.json`: the user's own, normally untracked.
    case project
    /// `~/.claude/settings.json`, for every project.
    case everywhere

    /// Whether writes keep `.wisp-backup` and `.wisp-previous` copies beside the file. A
    /// project's copies would sit in the repository, outside the local file's gitignore entry.
    public var keepsCopies: Bool { self == .everywhere }
}

/// Reads and edits `permissions` in a Claude Code settings file. Only `permissions.allow`
/// is ever changed; `ask`, `deny` and every other key stay as the user wrote them, and so
/// does the order of their rules.
public enum PermissionRulesFile {
    public enum Failure: Error, Equatable {
        case notAnObject
        case permissionsNotAnObject
        case listNotAnArray(String)
    }

    /// The string rules in each list, in the file's order.
    public struct Lists: Equatable, Sendable {
        public var allow: [String] = []
        public var ask: [String] = []
        public var deny: [String] = []

        public init(allow: [String] = [], ask: [String] = [], deny: [String] = []) {
            self.allow = allow
            self.ask = ask
            self.deny = deny
        }

        public var isEmpty: Bool { allow.isEmpty && ask.isEmpty && deny.isEmpty }
    }

    public static func lists(in data: Data) throws -> Lists {
        let permissions = try self.permissions(in: try root(data))
        return Lists(
            allow: try strings(permissions, "allow"), ask: try strings(permissions, "ask"),
            deny: try strings(permissions, "deny"))
    }

    /// Appends the rules not already in `permissions.allow`, creating the structure if needed.
    public static func adding(_ rules: [String], to data: Data) throws -> Data {
        var root = try self.root(data)
        var permissions = try self.permissions(in: root)
        var allow = try entries(permissions, "allow")
        for rule in rules where !allow.contains(.string(rule)) {
            allow.append(.string(rule))
        }
        permissions["allow"] = .array(allow)
        root["permissions"] = .object(permissions)
        return try SettingsJSON.encode(.object(root))
    }

    /// Takes `rule` out of `permissions.allow`; an emptied list stays as `[]`.
    public static func removing(_ rule: String, from data: Data) throws -> Data {
        var root = try self.root(data)
        var permissions = try self.permissions(in: root)
        permissions["allow"] = .array(try entries(permissions, "allow").filter { $0 != .string(rule) })
        root["permissions"] = .object(permissions)
        return try SettingsJSON.encode(.object(root))
    }

    /// The settings file for `scope`; nil for a project when the session's folder isn't known.
    public static func path(for scope: RuleScope, cwd: String, home: String, read: (String) -> String?) -> String? {
        switch scope {
        case .everywhere:
            return (home as NSString).appendingPathComponent(".claude/settings.json")
        case .project:
            return projectRoot(cwd: cwd, read: read).map {
                ($0 as NSString).appendingPathComponent(".claude/settings.local.json")
            }
        }
    }

    /// Claude Code loads `.claude/settings.local.json` from the repository root, and from the
    /// main checkout for a worktree, so a rule saved in a subfolder would never be read.
    /// Outside a repository it's the folder itself. `read` returns a file's contents.
    public static func projectRoot(cwd: String, read: (String) -> String?) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        let start = URL(fileURLWithPath: cwd).standardized.path
        var folder = start
        while true {
            let dotGit = (folder as NSString).appendingPathComponent(".git")
            if read((dotGit as NSString).appendingPathComponent("HEAD")) != nil { return folder }
            if let file = read(dotGit), let directory = GitHead.gitDirectory(fromDotGit: file, in: folder) {
                // A worktree's gitdir is <main>/.git/worktrees/<name>; a submodule's is the
                // parent's .git/modules, and its own folder is its root.
                if let range = directory.range(of: "/.git/worktrees/") { return String(directory[..<range.lowerBound]) }
                return folder
            }
            if folder == "/" { return start }
            folder = (folder as NSString).deletingLastPathComponent
        }
    }

    private static func root(_ data: Data) throws -> [String: JSONValue] {
        guard let root = try SettingsJSON.object(data) else { throw Failure.notAnObject }
        return root
    }

    private static func permissions(in root: [String: JSONValue]) throws -> [String: JSONValue] {
        switch root["permissions"] {
        case nil, .null?: return [:]
        case .object(let permissions)?: return permissions
        default: throw Failure.permissionsNotAnObject
        }
    }

    private static func entries(_ permissions: [String: JSONValue], _ key: String) throws -> [JSONValue] {
        switch permissions[key] {
        case nil, .null?: return []
        case .array(let entries)?: return entries
        default: throw Failure.listNotAnArray(key)
        }
    }

    private static func strings(_ permissions: [String: JSONValue], _ key: String) throws -> [String] {
        try entries(permissions, key).compactMap(\.stringValue)
    }
}
