import Foundation

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
            let group: JSONValue = .object([
                "matcher": .string(""),
                "hooks": .array([
                    .object([
                        "type": .string("command"), "command": .string(command), "timeout": .number(Double(timeout)),
                    ])
                ]),
            ])
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

    public static func isInstalled(in settings: Data) throws -> Bool {
        let root = try object(settings)
        return hooksObject(root["hooks"]).values.contains { value in
            guard case .array(let groups) = value else { return false }
            return groups.contains { group in
                guard case .array(let handlers) = group["hooks"] else { return false }
                return handlers.contains(where: isWisp)
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
