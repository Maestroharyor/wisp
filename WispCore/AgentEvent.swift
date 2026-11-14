import Foundation

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
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case subagentStop = "SubagentStop"
        /// Codex: the user interrupted the running turn.
        case interrupt = "Interrupt"
        case other

        /// Tool activity: frequent, and only about the tool, not the session's state.
        public static let toolActivity: [Kind] = [.preToolUse, .postToolUse, .subagentStop]
        public var isToolActivity: Bool { Self.toolActivity.contains(self) }
    }

    public let kind: Kind
    public let sessionID: String
    /// The working folder's name, the label people recognise a session by.
    public let project: String
    public let toolName: String?
    /// Pairs a PreToolUse with its PostToolUse.
    public let toolUseID: String?
    public internal(set) var toolInput: ToolInput
    /// The tool's input as sent, for replies that must echo it back (a plan approval).
    public let rawToolInput: JSONValue?
    /// The command, file or description the tool call is about.
    public internal(set) var summary: String
    public let message: String?
    public let notificationType: String?
    public let source: AgentSource
    /// Bundle id of the terminal or editor the agent runs in, added by the helper.
    public let terminal: String?
    /// The working folder's full path.
    public let cwd: String
    public let transcriptPath: String?
    /// The agent's process, when the helper could find it.
    public var process: AgentProcess?
    /// Where in the terminal the agent runs, when the helper sent it.
    public var terminalContext: TerminalContext?
    /// The helper process that sent this hook, so Wisp can tell when the agent stops waiting on it.
    public var hookPID: Int32?
    /// Set when a subagent made the call (Claude Code's `agent_id`); nil for the main agent.
    public let agentID: String?
    /// For SessionStart: how the session began ("startup", "resume", "clear", "compact", ...).
    public let startSource: String?
    /// For a prompt event: what the user typed, trimmed to one line (`PromptText`). Kept in
    /// memory only, never logged, saved or sent.
    public let promptText: String?
    /// Claude Code's permission mode for the session ("default", "plan", "acceptEdits",
    /// "bypassPermissions"), when the hook carries it.
    public let permissionMode: String?

    public enum DecodeFailure: Error { case notAnObject }

    /// The original hook format: the hook's JSON tagged with `wisp_source` and `wisp_terminal`.
    /// A missing source reads as Claude Code; `AgentProtocol.decode` turns unknown ones away
    /// before they get here.
    public static func decode(_ data: Data) throws -> AgentEvent {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let source = json["wisp_source"]?.stringValue.flatMap(AgentSource.init(rawValue:)) ?? .claude
        guard let event = source.adapter.parse(json, terminal: json["wisp_terminal"]?.stringValue) else {
            throw DecodeFailure.notAnObject
        }
        return event
    }

    /// The hook fields Claude Code and Codex share. Adapters build on this; everything else
    /// reads events through `AgentAdapter.parse`.
    init(json: JSONValue, source: AgentSource, terminal: String?) {
        let cwd = json["cwd"]?.stringValue ?? ""
        let input = json["tool_input"]
        self.kind = json["hook_event_name"]?.stringValue.flatMap(Kind.init(rawValue:)) ?? .other
        self.sessionID = json["session_id"]?.stringValue ?? "unknown"
        self.project = Self.projectName(cwd: cwd, source: source)
        self.toolName = json["tool_name"]?.stringValue
        self.toolUseID = json["tool_use_id"]?.stringValue
        self.toolInput = ToolInput(json: input)
        self.rawToolInput = input
        self.summary =
            input?["command"]?.stringValue ?? input?["file_path"]?.stringValue ?? input?["url"]?.stringValue
            ?? input?["description"]?.stringValue ?? input?["plan"]?.stringValue.flatMap(Self.planTitle) ?? ""
        self.message = json["message"]?.stringValue
        self.notificationType = json["notification_type"]?.stringValue
        self.source = source
        self.terminal = terminal.flatMap { $0.isEmpty ? nil : $0 }
        self.cwd = cwd
        self.transcriptPath = json["transcript_path"]?.stringValue
        self.startSource = json["source"]?.stringValue
        self.agentID = json["agent_id"]?.stringValue
        // Every adapter sends `prompt` with its prompt event (Gemini CLI's BeforeAgent, Copilot CLI's
        // userPromptSubmitted included).
        self.promptText = kind == .userPromptSubmit ? PromptText.trimmed(json["prompt"]?.stringValue) : nil
        self.permissionMode = json["permission_mode"]?.stringValue
    }

    /// What a permission request asks the user for.
    public var prompt: PermissionPrompt { source.adapter.prompt(tool: toolName) }

    /// A plan's first non-empty line without its heading marks ("Two agent fixes").
    static func planTitle(_ plan: String) -> String? {
        plan.split(whereSeparator: \.isNewline).lazy
            .map { $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// A session picked up again with `--resume`: its process, and the cost it reports, start over.
    public var isResume: Bool { kind == .sessionStart && startSource == "resume" }

    /// The working folder's name, or the agent's name when there's no usable folder.
    public static func projectName(cwd: String, source: AgentSource) -> String {
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        return cwd.isEmpty || folder == "/" ? source.adapter.fallbackProject : folder
    }
}

/// The parts of a tool call's input that tool activity labels are made from.
public struct ToolInput: Equatable, Sendable {
    public var command: String?
    public var filePath: String?
    public var notebookPath: String?
    public var url: String?
    public var pattern: String?
    public var query: String?
    public var description: String?
    public var subagentType: String?

    public init(
        command: String? = nil, filePath: String? = nil, notebookPath: String? = nil, url: String? = nil,
        pattern: String? = nil, query: String? = nil, description: String? = nil, subagentType: String? = nil
    ) {
        self.command = command
        self.filePath = filePath
        self.notebookPath = notebookPath
        self.url = url
        self.pattern = pattern
        self.query = query
        self.description = description
        self.subagentType = subagentType
    }

    init(json: JSONValue?) {
        self.init(
            command: json?["command"]?.stringValue, filePath: json?["file_path"]?.stringValue,
            notebookPath: json?["notebook_path"]?.stringValue, url: json?["url"]?.stringValue,
            pattern: json?["pattern"]?.stringValue, query: json?["query"]?.stringValue,
            description: json?["description"]?.stringValue, subagentType: json?["subagent_type"]?.stringValue)
    }
}

/// What a permission request asks for. Claude Code treats plans and questions as needing the
/// user's own input, so a plain allow doesn't answer them.
public enum PermissionPrompt: Equatable, Sendable {
    case tool
    /// ExitPlanMode: allowed by echoing the plan back as `updatedInput`.
    case plan
    /// AskUserQuestion: answered with the picked options in `updatedInput` (`QuestionReply`).
    case question

    /// A plan's input goes back with the approval, and a question's with its answers.
    public var keepsInput: Bool { self != .tool }

    public init(tool: String?) {
        switch tool {
        case "ExitPlanMode": self = .plan
        case "AskUserQuestion": self = .question
        default: self = .tool
        }
    }
}

/// The hook's stdout for a PermissionRequest decision.
public enum PermissionReply {
    /// The reply to an Allow or Deny in the notch. A plan gets its input back, or Claude Code
    /// ignores the allow; a question is answered with `QuestionReply`, never a bare decision.
    public static func answer(_ prompt: PermissionPrompt, allow: Bool, input: JSONValue?) -> String? {
        switch prompt {
        case .question: nil
        case .plan: json(allow: allow, updatedInput: input, denial: planDenied)
        case .tool: json(allow: allow)
        }
    }

    /// What Claude is told on a deny, with the reason typed in the notch if there is one.
    public static func denial(for prompt: PermissionPrompt, reason: String) -> String {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt == .plan { return reason.isEmpty ? planDenied : "\(planDenied) What to change: \(reason)" }
        return reason.isEmpty ? defaultDenial : "Denied from the Wisp notch: \(reason)"
    }

    public static let defaultDenial = "Denied from the Wisp notch."

    /// Tells Claude the plan was turned down, not the task, so it revises instead of stopping.
    public static let planDenied = "The plan wasn't approved from the Wisp notch. Keep planning and ask what to change."

    /// `updatedInput` goes with an allow only; a plan needs it or the allow is ignored.
    /// `denial` is what Claude is told on a deny.
    public static func json(
        allow: Bool, updatedInput: JSONValue? = nil, denial: String = defaultDenial
    ) -> String? {
        var decision: [String: JSONValue] = ["behavior": .string(allow ? "allow" : "deny")]
        if !allow { decision["message"] = .string(denial) }
        if allow, let updatedInput { decision["updatedInput"] = updatedInput }
        let output: JSONValue = .object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PermissionRequest"),
                "decision": .object(decision),
            ])
        ])
        return (try? JSONEncoder().encode(output)).map { String(decoding: $0, as: UTF8.self) }
    }
}
