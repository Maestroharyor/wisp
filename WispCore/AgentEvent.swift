import Foundation

/// One Claude Code hook call, as Wisp's helper forwards it.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
        case sessionEnd = "SessionEnd"
        case other
    }

    public let kind: Kind
    public let sessionID: String
    /// The working folder's name, the label people recognise a session by.
    public let project: String
    public let toolName: String?
    /// The command, file or description the tool call is about.
    public let summary: String
    public let message: String?
    public let notificationType: String?

    public static func decode(_ data: Data) throws -> AgentEvent {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let cwd = json["cwd"]?.stringValue ?? ""
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        let input = json["tool_input"]
        let summary =
            input?["command"]?.stringValue ?? input?["file_path"]?.stringValue ?? input?["url"]?.stringValue
            ?? input?["description"]?.stringValue ?? ""
        return AgentEvent(
            kind: json["hook_event_name"]?.stringValue.flatMap(Kind.init(rawValue:)) ?? .other,
            sessionID: json["session_id"]?.stringValue ?? "unknown",
            project: cwd.isEmpty || folder == "/" ? "Claude" : folder,
            toolName: json["tool_name"]?.stringValue,
            summary: summary,
            message: json["message"]?.stringValue,
            notificationType: json["notification_type"]?.stringValue
        )
    }
}

/// The hook's stdout for a PermissionRequest decision.
public enum PermissionReply {
    public static func json(allow: Bool) -> String? {
        var decision: [String: JSONValue] = ["behavior": .string(allow ? "allow" : "deny")]
        if !allow { decision["message"] = .string("Denied from the Wisp notch.") }
        let output: JSONValue = .object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PermissionRequest"),
                "decision": .object(decision),
            ])
        ])
        return (try? JSONEncoder().encode(output)).map { String(decoding: $0, as: UTF8.self) }
    }
}
