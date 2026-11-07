import Foundation

/// The coding agent a hook call came from, by its wire id (`"claude"`, `"codex"`, `"gemini"`, `"cursor"`,
/// `"copilot"`). Only ids in `AgentAdapters` can be made, so every source has an adapter.
public struct AgentSource: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    /// Nil for an id no adapter claims, so an unknown agent is never mistaken for a known one.
    public init?(rawValue: String) {
        guard AgentAdapters.adapter(id: rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    /// For the adapters' own ids, which can't check the registry they're part of.
    private init(registered id: String) { rawValue = id }

    public static let claude = AgentSource(registered: "claude")
    public static let codex = AgentSource(registered: "codex")
    public static let gemini = AgentSource(registered: "gemini")
    public static let cursor = AgentSource(registered: "cursor")
    public static let copilot = AgentSource(registered: "copilot")

    public init(from decoder: Decoder) throws {
        let id = try decoder.singleValueContainer().decode(String.self)
        guard let source = AgentSource(rawValue: id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown agent"))
        }
        self = source
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var adapter: AgentAdapter { AgentAdapters.adapter(for: self) }
    public var displayName: String { adapter.displayName }
    /// Hook events Wisp listens to.
    public var hookEvents: [String] { adapter.hookFile.events }
    /// Events whose hooks only report and never answer, so they run in the background.
    public var backgroundHookEvents: Set<String> { adapter.hookFile.backgroundEvents }
    /// Tool activity hooks, added only when the user turns tool activity on.
    public var toolHookEvents: [String] { adapter.hookFile.toolEvents }
}

/// What Wisp can do with an agent beyond showing its sessions.
public struct AgentCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Allow or Deny from the notch. Without it the agent is monitor only.
    public static let approve = AgentCapabilities(rawValue: 1 << 0)
    /// Answer the agent's multiple-choice questions from the notch.
    public static let answerQuestions = AgentCapabilities(rawValue: 1 << 1)
    /// An external status line command that sends live cost and context.
    public static let statusLine = AgentCapabilities(rawValue: 1 << 2)
    /// Plan usage windows, from the status line or the transcript.
    public static let limits = AgentCapabilities(rawValue: 1 << 3)
    /// PreCompact and PostCompact hooks.
    public static let compaction = AgentCapabilities(rawValue: 1 << 4)
    /// Always-allow rules written to the agent's own permission settings.
    public static let rules = AgentCapabilities(rawValue: 1 << 5)
    /// PreToolUse, PostToolUse and SubagentStop hooks.
    public static let toolActivity = AgentCapabilities(rawValue: 1 << 6)
}

/// Where an agent keeps its hooks and which ones Wisp adds there.
public struct HookFile: Equatable, Sendable {
    public enum Format: Equatable, Sendable {
        /// A `hooks` object of matcher groups inside Claude Code's settings.json, next to the
        /// user's other settings (and the status line).
        case claudeSettings
        /// Codex's hooks.json: the same `hooks` groups, in a file of their own.
        case codexHooks
        /// Gemini CLI's settings.json: the same `hooks` groups next to its other settings, with
        /// timeouts in milliseconds and no `async`.
        case geminiSettings
        /// Cursor's hooks.json: a `version` and, under `hooks`, a flat list of handlers for each
        /// event (no matcher groups).
        case cursorHooks
        /// A file of Wisp's own in Copilot CLI's hooks folder, as GitHub documents it: `"version": 1`
        /// and handlers listed straight under each event (no matcher groups), with `timeoutSec`.
        case copilotHooks

        /// What a timeout in seconds is multiplied by in this file.
        public var timeoutScale: Int { self == .geminiSettings ? 1000 : 1 }
        /// The handler's timeout field.
        public var timeoutKey: String { self == .copilotHooks ? "timeoutSec" : "timeout" }
        /// The `version` the file must carry, if any; the user's own stays.
        public var version: Int? { self == .copilotHooks || self == .cursorHooks ? 1 : nil }
        /// Handlers sit directly in each event's list instead of inside `{"matcher", "hooks"}`
        /// groups. No matcher means every call.
        public var flatHandlers: Bool { self == .copilotHooks || self == .cursorHooks }
        /// The file is Wisp's alone, so it goes once Wisp's hooks are taken out.
        public var ownedByWisp: Bool { self == .copilotHooks }
        /// The agent blocks the tool call when a hook command fails (Copilot CLI's preToolUse), so
        /// the command ends in `|| true`: a helper that's gone (Wisp moved or deleted) can't stop
        /// the agent's work. Cursor fails open on a failed command unless a hook sets `failClosed`.
        public var failsClosed: Bool { self == .copilotHooks }

        /// What the helper prints for `event` when Wisp has nothing to say: nothing, or for
        /// Cursor, which reads a hook's stdout as JSON, its "carry on" answer.
        public func silentReply(event: String?) -> String? {
            self == .cursorHooks ? CursorHooks.silentReply(event: event) : nil
        }

        /// Tool activity arrives only after each call (Cursor's postToolUse; its preToolUse is a
        /// permission hook Wisp leaves alone), so a finished call is shown without a start.
        public var reportsToolsWhenDone: Bool { self == .cursorHooks }
    }

    /// Relative to the home folder.
    public let path: String
    public let format: Format
    public let events: [String]
    /// Report-only events, installed with `"async": true`.
    public let backgroundEvents: Set<String>
    /// Added only while tool activity is on.
    public let toolEvents: [String]
    /// The file also holds the agent's status line command.
    public let statusLine: Bool
    /// What follows the helper's path in the hook command, so Wisp knows the agent.
    public let helperArguments: String

    /// Wisp holds a hook open for the user's answer, so the command carries the approval wait.
    public var waitsForApproval: Bool { events.contains(AgentEvent.Kind.permissionRequest.rawValue) }
    /// The agent says when it waits on the user (a Notification hook), so a session can show Needs you.
    public var reportsWaiting: Bool { events.contains(AgentEvent.Kind.notification.rawValue) }

    public var displayPath: String { "~/" + path }
    public func url(home: URL) -> URL { home.appendingPathComponent(path) }
}

/// What the user decided on a permission request, for the adapter to put in the agent's terms.
public enum AgentDecision: Equatable, Sendable {
    /// `input` is the tool's input, which a plan's approval echoes back.
    case allow(PermissionPrompt, input: JSONValue?)
    case deny(PermissionPrompt, reason: String)
    /// Answers to a question, keyed by each question's text.
    case answer(input: JSONValue, answers: [String: String])

    /// An Allow or Deny button, with no reason typed.
    public static func decide(_ prompt: PermissionPrompt, allow: Bool, input: JSONValue?) -> AgentDecision {
        allow ? .allow(prompt, input: input) : .deny(prompt, reason: "")
    }
}

/// Everything that differs between coding agents: names, hook files, how their hook JSON
/// reads and how a decision is written back. A value type with closures, so adapters are
/// plain `Sendable` data in a static registry.
public struct AgentAdapter: Sendable {
    public let source: AgentSource
    public let displayName: String
    /// SF Symbol for the agent's mark.
    public let symbol: String
    /// The session's name when it has no usable working folder.
    public let fallbackProject: String
    public let hookFile: HookFile
    public let capabilities: AgentCapabilities
    /// A setup step the user takes after connecting, for the connect dialog and Settings.
    public let setupNote: String?
    let readEvent: @Sendable (JSONValue, String?) -> AgentEvent
    let promptFor: @Sendable (String?) -> PermissionPrompt
    let write: @Sendable (AgentDecision) -> String?

    /// The hook's stdin JSON as an event; nil when it isn't a JSON object.
    public func parse(_ json: JSONValue, terminal: String?) -> AgentEvent? {
        guard case .object = json else { return nil }
        return readEvent(json, terminal)
    }

    /// What a permission request for `tool` asks the user for.
    public func prompt(tool: String?) -> PermissionPrompt { promptFor(tool) }

    /// The hook's stdout for a decision; nil to let the agent ask in the terminal.
    public func reply(_ decision: AgentDecision) -> String? { write(decision) }
}

/// Every agent Wisp knows, in the order Settings and onboarding list them.
public enum AgentAdapters {
    public static let all: [AgentAdapter] = [claude, codex, gemini, copilot, cursor]

    public static func adapter(id: String) -> AgentAdapter? { all.first { $0.source.rawValue == id } }

    /// `AgentSource` can only hold registered ids, so the fallback is never reached.
    public static func adapter(for source: AgentSource) -> AgentAdapter { adapter(id: source.rawValue) ?? claude }

    static let claude = AgentAdapter(
        source: .claude, displayName: "Claude Code", symbol: "sparkle", fallbackProject: "Claude",
        hookFile: HookFile(
            path: ".claude/settings.json", format: .claudeSettings,
            events: [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "SessionEnd",
                "PreCompact", "PostCompact",
            ],
            backgroundEvents: Set(["PreCompact", "PostCompact"] + toolEvents), toolEvents: toolEvents,
            statusLine: true, helperArguments: ""),
        capabilities: [.approve, .answerQuestions, .statusLine, .limits, .compaction, .rules, .toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: json, source: .claude, terminal: terminal) },
        promptFor: { PermissionPrompt(tool: $0) },
        write: { decision in
            switch decision {
            case .allow(let prompt, let input): PermissionReply.answer(prompt, allow: true, input: input)
            case .deny(let prompt, let reason):
                PermissionReply.json(allow: false, denial: PermissionReply.denial(for: prompt, reason: reason))
            case .answer(let input, let answers): QuestionReply.json(input: input, answers: answers)
            }
        })

    /// Codex follows Claude Code's hook field names (session_id, tool_input, ...) with a few
    /// extensions (turn_id, model), so the common reader serves both.
    static let codex = AgentAdapter(
        source: .codex, displayName: "Codex", symbol: "chevron.left.forwardslash.chevron.right",
        fallbackProject: "Codex",
        hookFile: HookFile(
            path: ".codex/hooks.json", format: .codexHooks,
            // No Notification event in Codex.
            events: [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd", "PreCompact",
                "PostCompact",
            ],
            // Compaction hooks stay synchronous, as before Codex documented `async`, so hooks
            // users already trusted in /hooks keep their hash.
            backgroundEvents: Set(toolEvents), toolEvents: toolEvents, statusLine: false,
            helperArguments: " --source codex"),
        capabilities: [.approve, .limits, .compaction, .toolActivity],
        setupNote: "Codex asks you to trust new hooks once: run /hooks in Codex.",
        readEvent: { json, terminal in CodexPatch.labelled(AgentEvent(json: json, source: .codex, terminal: terminal))
        },
        // Codex has no plan or question prompts: every request is a tool.
        promptFor: { _ in .tool },
        write: { decision in
            switch decision {
            // `updatedInput` is reserved in Codex and fails closed, so an allow never carries it.
            case .allow: PermissionReply.json(allow: true)
            case .deny(let prompt, let reason):
                PermissionReply.json(allow: false, denial: PermissionReply.denial(for: prompt, reason: reason))
            case .answer: nil
            }
        })

    /// Monitor only. Gemini CLI's BeforeTool hook runs (and blocks) before its policy check, for
    /// every tool call. It can deny a call, rewrite its input or add a confirmation (`ask`), but
    /// its allow never skips Gemini's own confirmation, so Allow in the notch would still prompt
    /// in the terminal. Wisp shows the session and its prompts; the terminal answers them.
    static let gemini = AgentAdapter(
        source: .gemini, displayName: "Gemini CLI", symbol: "diamond", fallbackProject: "Gemini",
        hookFile: HookFile(
            path: ".gemini/settings.json", format: .geminiSettings,
            // AfterTool is always on: it's the first event after a tool confirmation answered in
            // the terminal, so Needs you clears. BeforeModel would fire as often and carry the
            // whole conversation in every call. Gemini hooks are synchronous, so it costs each tool
            // call a helper launch, which hands the event off without waiting for Wisp.
            events: [
                "SessionStart", "BeforeAgent", "Notification", "AfterTool", "AfterAgent", "SessionEnd", "PreCompress",
            ],
            backgroundEvents: [], toolEvents: ["BeforeTool"], statusLine: false,
            helperArguments: " --source gemini"),
        capabilities: [.toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in
            AgentEvent(json: GeminiHooks.renamed(json), source: .gemini, terminal: terminal)
        },
        promptFor: { _ in .tool },
        write: { _ in nil })

    /// Monitor only. Cursor documents allow, deny and ask for beforeShellExecution and
    /// beforeMCPExecution, but Cursor staff said (forum, March 2026) that only deny is enforced
    /// there: allow never skips Cursor's own approval and ask is ignored. preToolUse enforces
    /// allow and deny but has no ask, so it can't hand a call back to Cursor's prompt, and it
    /// would hold every tool call. All of these are permission hooks, which block the action when
    /// their output can't be read, so Wisp installs none of them. Tool activity comes from
    /// postToolUse, once a tool has finished. Cursor has no event for "waiting on you", so
    /// there's no Needs you either.
    static let cursor = AgentAdapter(
        source: .cursor, displayName: "Cursor", symbol: "cursorarrow", fallbackProject: "Cursor",
        hookFile: HookFile(
            path: ".cursor/hooks.json", format: .cursorHooks,
            events: ["sessionStart", "beforeSubmitPrompt", "stop", "sessionEnd", "preCompact"],
            backgroundEvents: [], toolEvents: ["postToolUse"], statusLine: false,
            helperArguments: " --source cursor"),
        capabilities: [.toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in
            AgentEvent(json: CursorHooks.renamed(json), source: .cursor, terminal: terminal)
        },
        promptFor: { _ in .tool },
        write: { _ in nil })

    /// Monitor only. Copilot CLI's PermissionRequest hook can allow or deny, but it runs before
    /// Copilot's own rules, session approvals and auto-allow, for every request but reads, so a
    /// card would pop for each shell command and edit Copilot would have let through, and a tool
    /// approved for the session would ask again. preToolUse is the same. Wisp shows the session;
    /// a `permission_prompt` notification (sent only when Copilot really shows a prompt) is Needs
    /// you, and the terminal answers. Hooks go in a file of Wisp's own under PascalCase names, so
    /// Copilot sends Claude Code's field names and tool names (Bash, Read, Edit, Write).
    static let copilot = AgentAdapter(
        source: .copilot, displayName: "Copilot CLI", symbol: "airplane", fallbackProject: "Copilot",
        hookFile: HookFile(
            path: ".copilot/hooks/wisp.json", format: .copilotHooks,
            // PostToolUse runs only after a tool succeeds and PostToolUseFailure after one fails;
            // both are always on, so a prompt answered in the terminal leaves Needs you once the
            // tool has run. There's no event after PreCompact.
            events: [
                "SessionStart", "UserPromptSubmit", "Notification", "PostToolUse", "PostToolUseFailure", "Stop",
                "SessionEnd", "PreCompact",
            ],
            backgroundEvents: [], toolEvents: ["PreToolUse"], statusLine: false,
            helperArguments: " --source copilot"),
        capabilities: [.toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in
            AgentEvent(json: CopilotHooks.normalized(json), source: .copilot, terminal: terminal)
        },
        promptFor: { _ in .tool },
        write: { _ in nil })

    private static let toolEvents = AgentEvent.Kind.toolActivity.map(\.rawValue)
}

/// Cursor's hook input: camelCase event names, `conversation_id` on every event (sessionStart's
/// `session_id` is the same value), `workspace_roots` for the project and `cwd` only on tool
/// events. Tool calls use Claude Code's `tool_name`, `tool_input` and `tool_use_id`.
public enum CursorHooks {
    /// Cursor's event names in Wisp's terms. Anything else, Claude Code's names included,
    /// reads as `.other`.
    static let kinds: [String: AgentEvent.Kind] = [
        "sessionStart": .sessionStart, "sessionEnd": .sessionEnd, "beforeSubmitPrompt": .userPromptSubmit,
        "stop": .stop, "preCompact": .preCompact, "postToolUse": .postToolUse,
    ]

    /// Cursor's "carry on" answer for `event`. beforeSubmitPrompt's documented output is
    /// `continue`, so it says so; every other hook gets an empty object. Claude Code's name for
    /// the prompt hook counts too, for Claude Code hooks Cursor runs (`isImported`).
    public static func silentReply(event: String?) -> String {
        event == "beforeSubmitPrompt" || event == "UserPromptSubmit" ? #"{"continue":true}"# : "{}"
    }

    /// Cursor also runs the hooks in Claude Code's settings files (Settings › Agents ›
    /// Third-Party Imports, on by default), so Wisp's Claude Code hooks fire for Cursor's
    /// sessions too. Their payload carries `cursor_version`, which Claude Code never sends.
    /// Those calls are dropped: connecting Cursor shows its sessions, once.
    public static func isImported(_ payload: Data, source: AgentSource) -> Bool {
        guard source != .cursor, let json = try? JSONDecoder().decode(JSONValue.self, from: payload) else {
            return false
        }
        return json["cursor_version"] != nil
    }

    /// The payload in the common reader's field names. The first workspace root names the
    /// session, so a tool run in a subfolder doesn't rename it.
    static func renamed(_ json: JSONValue) -> JSONValue {
        guard case .object(var fields) = json else { return json }
        let kind = fields["hook_event_name"]?.stringValue.flatMap { kinds[$0] }
        fields["hook_event_name"] = kind.map { .string($0.rawValue) }
        if let id = fields["conversation_id"] ?? fields["session_id"] { fields["session_id"] = id }
        if case .array(let roots) = fields["workspace_roots"], let root = roots.first?.stringValue, !root.isEmpty {
            fields["cwd"] = .string(root)
        }
        return .object(fields)
    }
}

/// Copilot CLI sends Claude Code's snake_case fields to hooks configured under PascalCase event
/// names, and camelCase ones (`sessionId`, `toolName`, `toolArgs`) under camelCase names. Its
/// reference also shows the Notification payload with `sessionId`. Both read the same here.
public enum CopilotHooks {
    /// The notification type Copilot CLI sends when it shows a permission prompt.
    public static let permissionPrompt = "permission_prompt"

    /// Copilot's event names, PascalCase and camelCase, in Wisp's terms. Anything else reads as
    /// `.other`.
    static let kinds: [String: AgentEvent.Kind] = [
        "SessionStart": .sessionStart, "sessionStart": .sessionStart,
        "UserPromptSubmit": .userPromptSubmit, "userPromptSubmitted": .userPromptSubmit,
        "Notification": .notification, "notification": .notification,
        "PreToolUse": .preToolUse, "preToolUse": .preToolUse,
        "PostToolUse": .postToolUse, "postToolUse": .postToolUse,
        "PostToolUseFailure": .postToolUse, "postToolUseFailure": .postToolUse,
        "Stop": .stop, "agentStop": .stop,
        "SessionEnd": .sessionEnd, "sessionEnd": .sessionEnd,
        "PreCompact": .preCompact, "preCompact": .preCompact,
    ]

    /// camelCase fields Wisp reads, by the snake_case name they fill in when it's missing.
    private static let camelCase = [
        "hook_event_name": "hookEventName", "session_id": "sessionId", "transcript_path": "transcriptPath",
        "tool_name": "toolName", "notification_type": "notificationType",
    ]

    /// The payload with Claude Code's field names and Wisp's event name, so the common reader
    /// takes it.
    static func normalized(_ json: JSONValue) -> JSONValue {
        guard case .object(var fields) = json else { return json }
        for (snake, camel) in camelCase where fields[snake] == nil { fields[snake] = fields[camel] }
        let kind = fields["hook_event_name"]?.stringValue.flatMap { kinds[$0] }
        fields["hook_event_name"] = kind.map { .string($0.rawValue) }
        if let input = (fields["tool_input"] ?? fields["toolArgs"]).flatMap(decodedArguments) {
            fields["tool_input"] = withFilePath(input)
        }
        return .object(fields)
    }

    /// The tool's arguments may come as a JSON string (camelCase `toolArgs` does).
    private static func decodedArguments(_ value: JSONValue) -> JSONValue? {
        guard let text = value.stringValue else { return value }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Copilot's file tools (view, edit, create) name the file `path`.
    private static func withFilePath(_ input: JSONValue) -> JSONValue {
        guard case .object(var fields) = input, fields["file_path"] == nil, let path = fields["path"] else {
            return input
        }
        fields["file_path"] = path
        return .object(fields)
    }
}

/// Gemini CLI's hook input uses Claude Code's field names (session_id, cwd, transcript_path,
/// tool_name, tool_input) under its own event names.
public enum GeminiHooks {
    /// The Notification type Gemini CLI sends when it asks the user to confirm a tool call.
    public static let toolPermission = "ToolPermission"

    /// Gemini CLI's event names in Wisp's terms. Anything else, Claude Code's names included,
    /// reads as `.other`.
    static let kinds: [String: AgentEvent.Kind] = [
        "SessionStart": .sessionStart, "SessionEnd": .sessionEnd, "BeforeAgent": .userPromptSubmit,
        "AfterAgent": .stop, "Notification": .notification, "PreCompress": .preCompact, "BeforeTool": .preToolUse,
        "AfterTool": .postToolUse,
    ]

    /// The payload with `hook_event_name` renamed, so the common reader takes it.
    static func renamed(_ json: JSONValue) -> JSONValue {
        guard case .object(var fields) = json else { return json }
        let kind = fields["hook_event_name"]?.stringValue.flatMap { kinds[$0] }
        fields["hook_event_name"] = kind.map { .string($0.rawValue) }
        return .object(fields)
    }
}

/// Codex edits files with `apply_patch`, whose `tool_input.command` is the whole patch.
public enum CodexPatch {
    private static let markers = ["*** Update File:", "*** Add File:", "*** Delete File:"]

    /// The first file a patch touches.
    public static func firstPath(_ patch: String) -> String? {
        for line in patch.split(whereSeparator: \.isNewline) {
            guard let marker = markers.first(where: { line.hasPrefix($0) }) else { continue }
            let path = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty { return path }
        }
        return nil
    }

    /// A patch reads as an edit of its first file; its body never becomes a label or summary.
    static func labelled(_ event: AgentEvent) -> AgentEvent {
        guard event.toolName == "apply_patch" else { return event }
        var event = event
        let path = event.toolInput.command.flatMap(firstPath)
        event.toolInput.command = nil
        event.toolInput.filePath = path
        event.summary = path ?? ""
        return event
    }
}
