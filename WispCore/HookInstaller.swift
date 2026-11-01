import Foundation

/// Where Wisp's agent hooks lead.
public enum HookLink: Equatable, Sendable {
    case none
    case this
    /// This copy's hooks, from an older version: some events Wisp now uses are missing.
    case outdated
    case other
}

/// Adds and removes Wisp's hooks in Claude Code's settings.json or Codex's hooks.json
/// (the same shape) without touching the user's own settings or hooks. Wisp's entries
/// are recognised by the helper's name.
public enum HookInstaller {
    public enum Failure: Error { case notAnObject }

    public static let helperName = "wisp-agent"
    public static let events = AgentSource.claude.hookEvents
    /// Seconds a permission prompt waits for the notch before Claude Code shows its own.
    public static let approvalTimeout = 120

    public static func install(into settings: Data, command: String, source: AgentSource = .claude) throws -> Data {
        var root = try object(settings)
        var hooks = stripped(root["hooks"])
        for event in source.hookEvents {
            let timeout = event == "PermissionRequest" ? approvalTimeout : 5
            var handler: [String: JSONValue] = [
                "type": .string("command"), "command": .string(command), "timeout": .number(Double(timeout)),
            ]
            if source.backgroundHookEvents.contains(event) { handler["async"] = .bool(true) }
            let group: JSONValue = .object(["matcher": .string(""), "hooks": .array([.object(handler)])])
            var groups: [JSONValue] = []
            if case .array(let existing) = hooks[event] { groups = existing }
            hooks[event] = .array(groups + [group])
        }
        root["hooks"] = .object(hooks)
        return try encode(.object(root))
    }

    public static func remove(from settings: Data) throws -> Data {
        var root = try object(settings)
        let hooks = stripped(root["hooks"])
        root["hooks"] = hooks.isEmpty ? nil : .object(hooks)
        return try encode(.object(root))
    }

    /// The hook command for `helper`: the path in POSIX single quotes, tagged for Codex.
    public static func command(helper: String, source: AgentSource) -> String {
        source == .claude ? quote(helper) : quote(helper) + " --source codex"
    }

    /// `text` as one POSIX shell word in single quotes.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The inverse of `quote`: single-quoted runs joined by `\'`. Anything else is nil.
    public static func unquote(_ word: String) -> String? {
        var result = ""
        var rest = Substring(word)
        while !rest.isEmpty {
            if rest.hasPrefix("\\'") {
                result += "'"
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("'") {
                let body = rest.dropFirst()
                guard let end = body.firstIndex(of: "'") else { return nil }
                result += body[..<end]
                rest = body[body.index(after: end)...]
            } else {
                return nil
            }
        }
        return result
    }

    /// Whether the hooks call this copy's helper, another copy's (a dev build, a moved app),
    /// or no Wisp at all. Another copy's helper talks to that copy, so this one hears nothing.
    public static func link(in settings: Data, helper: String, source: AgentSource) throws -> HookLink {
        let commands = try wispCommands(in: settings)
        if commands.isEmpty { return .none }
        let mine = command(helper: helper, source: source)
        guard commands.allSatisfy({ $0.command == mine }) else { return .other }
        return Set(commands.map(\.event)) == Set(source.hookEvents) ? .this : .outdated
    }

    public static func isInstalled(in settings: Data) throws -> Bool {
        try !wispCommands(in: settings).isEmpty
    }

    private static func wispCommands(in settings: Data) throws -> [(event: String, command: String)] {
        let root = try object(settings)
        return hooksObject(root["hooks"]).flatMap { event, value -> [(event: String, command: String)] in
            guard case .array(let groups) = value else { return [] }
            return groups.flatMap { group -> [(event: String, command: String)] in
                guard case .array(let handlers) = group["hooks"] else { return [] }
                return handlers.filter(isWisp).compactMap { handler in
                    handler["command"]?.stringValue.map { (event, $0) }
                }
            }
        }
    }

    private static func isWisp(_ handler: JSONValue) -> Bool {
        handler["command"]?.stringValue?.contains(helperName) ?? false
    }

    /// The hooks object minus Wisp's handlers, dropping groups and events that only held
    /// Wisp's. The user's own empty entries stay as they were.
    private static func stripped(_ hooks: JSONValue?) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (event, value) in hooksObject(hooks) {
            guard case .array(let groups) = value else {
                result[event] = value
                continue
            }
            let kept = groups.compactMap(strippedGroup)
            if !kept.isEmpty || groups.isEmpty { result[event] = .array(kept) }
        }
        return result
    }

    private static func strippedGroup(_ group: JSONValue) -> JSONValue? {
        guard case .object(var fields) = group, case .array(let handlers) = fields["hooks"] else { return group }
        let kept = handlers.filter { !isWisp($0) }
        if kept.isEmpty, !handlers.isEmpty { return nil }
        fields["hooks"] = .array(kept)
        return .object(fields)
    }

    private static func hooksObject(_ value: JSONValue?) -> [String: JSONValue] {
        if case .object(let hooks) = value { return hooks }
        return [:]
    }

    private static func object(_ data: Data) throws -> [String: JSONValue] {
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard case .object(let root) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw Failure.notAnObject
        }
        return root
    }

    private static func encode(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
