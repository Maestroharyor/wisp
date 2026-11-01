import Foundation

/// The coding agent a hook call came from.
public enum AgentSource: String, Equatable, Sendable {
    case claude
    case codex

    public var displayName: String { self == .claude ? "Claude Code" : "Codex" }

    /// Hook events Wisp listens to. Codex has no Notification event.
    public var hookEvents: [String] {
        switch self {
        case .claude:
            [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "SessionEnd",
                "PreCompact", "PostCompact",
            ]
        case .codex:
            [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd", "PreCompact",
                "PostCompact",
            ]
        }
    }

    /// Events whose hooks only report and never answer, so Claude Code may run them in the
    /// background (`"async": true`). Codex documents no such option.
    public var backgroundHookEvents: Set<String> {
        self == .claude ? ["PreCompact", "PostCompact"] : []
    }
}

/// One coding-agent hook call, as Wisp's helper forwards it.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
        case sessionEnd = "SessionEnd"
        case preCompact = "PreCompact"
        case postCompact = "PostCompact"
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
    public let source: AgentSource
    /// Bundle id of the terminal or editor the agent runs in, added by the helper.
    public let terminal: String?
    /// The working folder's full path.
    public let cwd: String
    public let transcriptPath: String?
    /// For SessionStart: how the session began ("startup", "resume", "clear", "compact", ...).
    public let startSource: String?

    /// Today's hook format: the hook's JSON tagged with `wisp_source` and `wisp_terminal`.
    public static func decode(_ data: Data) throws -> AgentEvent {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        return AgentEvent(
            json: json,
            source: json["wisp_source"]?.stringValue.flatMap(AgentSource.init(rawValue:)) ?? .claude,
            terminal: json["wisp_terminal"]?.stringValue)
    }

    public init(json: JSONValue, source: AgentSource, terminal: String?) {
        let cwd = json["cwd"]?.stringValue ?? ""
        let input = json["tool_input"]
        self.kind = json["hook_event_name"]?.stringValue.flatMap(Kind.init(rawValue:)) ?? .other
        self.sessionID = json["session_id"]?.stringValue ?? "unknown"
        self.project = Self.projectName(cwd: cwd, source: source)
        self.toolName = json["tool_name"]?.stringValue
        self.summary =
            input?["command"]?.stringValue ?? input?["file_path"]?.stringValue ?? input?["url"]?.stringValue
            ?? input?["description"]?.stringValue ?? ""
        self.message = json["message"]?.stringValue
        self.notificationType = json["notification_type"]?.stringValue
        self.source = source
        self.terminal = terminal.flatMap { $0.isEmpty ? nil : $0 }
        self.cwd = cwd
        self.transcriptPath = json["transcript_path"]?.stringValue
        self.startSource = json["source"]?.stringValue
    }

    /// A session picked up again with `--resume`: its process, and the cost it reports, start over.
    public var isResume: Bool { kind == .sessionStart && startSource == "resume" }

    /// The working folder's name, or the agent's name when there's no usable folder.
    public static func projectName(cwd: String, source: AgentSource) -> String {
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        return cwd.isEmpty || folder == "/" ? (source == .codex ? "Codex" : "Claude") : folder
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
