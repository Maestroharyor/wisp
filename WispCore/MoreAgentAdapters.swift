import Foundation

/// Hook adapters for Qwen Code, Qoder CLI, Droid, CodeBuddy, Kimi Code, Grok and Mistral Vibe.
/// Qwen Code and Qoder CLI document a PermissionRequest hook that fires only when they would ask
/// and takes Claude Code's decision reply, so Wisp answers them. The others report their
/// sessions only: their hooks either run before every tool call (and would hold each one for a
/// card) or can't approve at all, and their docs don't confirm an approval reply.
extension AgentAdapters {
    /// Claude Code's lifecycle hooks plus PermissionRequest, for agents that copy its hooks.
    private static let claudeLifecycle = [
        "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "SessionEnd", "PreCompact",
        "PostCompact",
    ]

    /// The same without PermissionRequest. PostToolUse is always on, so a prompt answered in the
    /// terminal leaves Needs you once the tool has run (as for Copilot CLI).
    private static let claudeReportOnly = [
        "SessionStart", "UserPromptSubmit", "Notification", "PostToolUse", "Stop", "SessionEnd", "PreCompact",
    ]

    /// Allow and deny in Claude Code's PermissionRequest reply, which Qwen Code and Qoder CLI
    /// document. They have no plan or question prompts Wisp knows, so every request is a tool.
    private static let claudeDecision: @Sendable (AgentDecision) -> String? = { decision in
        switch decision {
        case .allow: PermissionReply.json(allow: true)
        case .deny(let prompt, let reason):
            PermissionReply.json(allow: false, denial: PermissionReply.denial(for: prompt, reason: reason))
        case .answer: nil
        }
    }

    /// Qwen Code's hooks follow Claude Code's: the same fields and event names, and a
    /// PermissionRequest that fires when its permission dialog shows.
    /// https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/
    static let qwen = AgentAdapter(
        source: .qwen, displayName: "Qwen Code", symbol: "q.circle", fallbackProject: "Qwen",
        hookFile: HookFile(
            path: ".qwen/settings.json", format: .qwenSettings, events: claudeLifecycle,
            // Qwen documents `async` only in its Chinese reference, so the tool hooks stay
            // synchronous; the helper hands them off without waiting either way.
            backgroundEvents: [], toolEvents: toolEvents, statusLine: false, helperArguments: " --source qwen"),
        capabilities: [.approve, .compaction, .toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: json, source: .qwen, terminal: terminal) },
        promptFor: { _ in .tool },
        write: claudeDecision)

    /// Qoder CLI's hooks follow Claude Code's, with `async` and a PermissionRequest whose reply
    /// is allow or deny (no ask). https://docs.qoder.com/cli/hooks
    static let qoder = AgentAdapter(
        source: .qoder, displayName: "Qoder CLI", symbol: "q.square", fallbackProject: "Qoder",
        hookFile: HookFile(
            path: ".qoder/settings.json", format: .claudeSettings, events: claudeLifecycle,
            backgroundEvents: Set(["PreCompact", "PostCompact"] + toolEvents), toolEvents: toolEvents,
            statusLine: false, helperArguments: " --source qoder"),
        capabilities: [.approve, .compaction, .toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: json, source: .qoder, terminal: terminal) },
        promptFor: { _ in .tool },
        write: claudeDecision)

    /// Report only. Droid's one permission hook is PreToolUse, which runs before every tool
    /// call, so holding it for a card would stop each call Droid would have let through. A
    /// `permission_prompt` notification (sent when Droid waits on you) is Needs you.
    /// https://docs.factory.ai/reference/hooks-reference
    static let droid = AgentAdapter(
        source: .droid, displayName: "Droid", symbol: "cpu", fallbackProject: "Droid",
        hookFile: HookFile(
            path: ".factory/hooks.json", format: .factoryHooks, events: claudeReportOnly, backgroundEvents: [],
            toolEvents: ["PreToolUse"], statusLine: false, helperArguments: " --source droid",
            seedPath: ".factory/settings.json"),
        capabilities: [.toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: json, source: .droid, terminal: terminal) },
        promptFor: { _ in .tool },
        write: { _ in nil })

    /// Report only. CodeBuddy lists a PermissionRequest event but documents no reply for it,
    /// and its PreToolUse runs before every tool call. https://www.codebuddy.cn/docs/cli/hooks
    static let codebuddy = AgentAdapter(
        source: .codebuddy, displayName: "CodeBuddy", symbol: "person.2", fallbackProject: "CodeBuddy",
        hookFile: HookFile(
            path: ".codebuddy/settings.json", format: .claudeSettings, events: claudeReportOnly,
            backgroundEvents: [], toolEvents: ["PreToolUse"], statusLine: false,
            helperArguments: " --source codebuddy"),
        capabilities: [.toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: json, source: .codebuddy, terminal: terminal) },
        promptFor: { _ in .tool },
        write: { _ in nil })

    /// Report only. Kimi Code's PermissionRequest and PermissionResult only observe a prompt,
    /// and its PreToolUse can block but not approve, so a prompt is Needs you and is answered in
    /// the terminal. https://moonshotai.github.io/kimi-code/en/customization/hooks
    static let kimi = AgentAdapter(
        source: .kimi, displayName: "Kimi Code", symbol: "moon", fallbackProject: "Kimi",
        hookFile: HookFile(
            path: ".kimi-code/config.toml", format: .kimiConfig,
            events: [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "PermissionResult", "PostToolUse", "Stop",
                "Interrupt", "SessionEnd", "PreCompact", "PostCompact",
            ],
            backgroundEvents: [], toolEvents: ["PreToolUse"], statusLine: false, helperArguments: " --source kimi",
            permissionRequestObservesOnly: true),
        capabilities: [.compaction, .toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: KimiHooks.renamed(json), source: .kimi, terminal: terminal) },
        promptFor: { _ in .tool },
        write: { _ in nil })

    /// Report only. Grok has no hook for a permission prompt; its PreToolUse can only deny.
    /// Hooks go in a file of Wisp's own. https://docs.x.ai/build/features/hooks
    static let grok = AgentAdapter(
        source: .grok, displayName: "Grok", symbol: "bolt.horizontal", fallbackProject: "Grok",
        hookFile: HookFile(
            path: ".grok/hooks/wisp.json", format: .grokHooks,
            events: ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "PreCompact", "PostCompact"],
            backgroundEvents: [], toolEvents: ["PreToolUse", "PostToolUse"], statusLine: false,
            helperArguments: " --source grok"),
        capabilities: [.compaction, .toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: GrokHooks.normalized(json), source: .grok, terminal: terminal)
        },
        promptFor: { _ in .tool },
        write: { _ in nil })

    /// Report only. Mistral Vibe has three hooks: before and after each tool call and after a
    /// turn. pre_tool runs before the permission prompt and can only deny. With no session or
    /// prompt event, the tool hooks are what show a session working, so they're always on.
    /// https://docs.mistral.ai/vibe/code/cli/hooks
    static let vibe = AgentAdapter(
        source: .vibe, displayName: "Mistral Vibe", symbol: "wind", fallbackProject: "Vibe",
        hookFile: HookFile(
            path: ".vibe/hooks.toml", format: .vibeHooks, events: ["pre_tool", "post_tool", "post_agent"],
            backgroundEvents: [], toolEvents: [], statusLine: false, helperArguments: " --source vibe"),
        capabilities: [.toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in AgentEvent(json: VibeHooks.renamed(json), source: .vibe, terminal: terminal) },
        promptFor: { _ in .tool },
        write: { _ in nil })
}

/// Kimi Code sends Claude Code's field names. Its PermissionRequest fires just before it waits
/// for the user and PermissionResult once that's answered; both only observe.
public enum KimiHooks {
    static func renamed(_ json: JSONValue) -> JSONValue {
        guard case .object(var fields) = json else { return json }
        switch fields["hook_event_name"]?.stringValue {
        case "PermissionRequest":
            fields["hook_event_name"] = .string(AgentEvent.Kind.notification.rawValue)
            fields["notification_type"] = .string(CopilotHooks.permissionPrompt)
        case "PermissionResult":
            fields["hook_event_name"] = .string(AgentEvent.Kind.postToolUse.rawValue)
            fields["tool_use_id"] = nil
        default: break
        }
        return .object(fields)
    }
}

/// Grok sends camelCase fields (`hookEventName`, `sessionId`, `toolName`, `toolInput`) and the
/// workspace root beside the working folder.
public enum GrokHooks {
    /// Grok sets this for every hook it runs, its own and the Claude Code and Cursor hooks it
    /// also reads.
    static let eventVariable = "GROK_HOOK_EVENT"

    /// Grok also runs the hooks in Claude Code's and Cursor's files, so Wisp's hooks there fire
    /// for Grok's sessions too. Those calls are dropped; Grok's own hooks report its sessions.
    public static func isImported(environment: [String: String], source: AgentSource) -> Bool {
        source != .grok && environment[eventVariable] != nil
    }

    private static let camelCase = [
        "hook_event_name": "hookEventName", "session_id": "sessionId", "tool_name": "toolName",
        "tool_input": "toolInput", "tool_use_id": "toolUseId", "transcript_path": "transcriptPath",
    ]

    static func normalized(_ json: JSONValue) -> JSONValue {
        guard case .object(var fields) = json else { return json }
        for (snake, camel) in camelCase where fields[snake] == nil { fields[snake] = fields[camel] }
        // The workspace root names the session, so a tool run in a subfolder doesn't rename it.
        if let root = fields["workspaceRoot"]?.stringValue, !root.isEmpty { fields["cwd"] = .string(root) }
        return .object(fields)
    }
}

/// Mistral Vibe's hook types in Wisp's terms; its fields are Claude Code's, with `tool_call_id`
/// for the call.
public enum VibeHooks {
    static let kinds: [String: AgentEvent.Kind] = [
        "pre_tool": .preToolUse, "post_tool": .postToolUse, "post_agent": .stop,
    ]

    static func renamed(_ json: JSONValue) -> JSONValue {
        guard case .object(var fields) = json else { return json }
        let kind = fields["hook_event_name"]?.stringValue.flatMap { kinds[$0] }
        fields["hook_event_name"] = kind.map { .string($0.rawValue) }
        if fields["tool_use_id"] == nil { fields["tool_use_id"] = fields["tool_call_id"] }
        return .object(fields)
    }
}
