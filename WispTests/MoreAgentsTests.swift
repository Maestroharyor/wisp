import XCTest

@testable import WispCore

/// The hook adapters for Qwen Code, Qoder CLI, Droid, CodeBuddy, Kimi Code, Grok and Mistral Vibe.
/// Payloads follow each agent's hooks reference (checked 2026-11-14): field names, event names
/// and reply shapes are the documented ones, values are made up. None of these agents was
/// installed, so none of these came from a live run.
final class MoreAgentsTests: XCTestCase {
    private func event(_ source: AgentSource, _ text: String) throws -> AgentEvent {
        try XCTUnwrap(
            source.adapter.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), terminal: nil))
    }

    private func reply(_ source: AgentSource, allow: Bool, reason: String = "") throws -> JSONValue {
        let decision: AgentDecision = allow ? .allow(.tool, input: nil) : .deny(.tool, reason: reason)
        let text = try XCTUnwrap(source.adapter.reply(decision))
        return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testEveryNewSourceIsRegisteredWithANameAndSymbol() {
        let expected: [(AgentSource, String, String)] = [
            (.qwen, "qwen", "Qwen Code"), (.qoder, "qoder", "Qoder CLI"), (.droid, "droid", "Droid"),
            (.codebuddy, "codebuddy", "CodeBuddy"), (.kimi, "kimi", "Kimi Code"), (.grok, "grok", "Grok"),
            (.vibe, "vibe", "Mistral Vibe"),
        ]
        for (source, id, name) in expected {
            XCTAssertEqual(AgentSource(rawValue: id), source)
            XCTAssertEqual(source.displayName, name)
            XCTAssertFalse(source.adapter.symbol.isEmpty)
            XCTAssertEqual(source.adapter.hookFile.helperArguments, " --source \(id)")
            XCTAssertFalse(source.adapter.hookFile.statusLine)
        }
        XCTAssertEqual(Set(AgentAdapters.all.map(\.source.rawValue)).count, AgentAdapters.all.count)
    }

    // MARK: Qwen Code (approve)

    private let qwenBase =
        #""session_id":"q-1","transcript_path":"/Users/me/.qwen/tmp/q-1.jsonl","cwd":"/Users/me/shop","timestamp":"2026-11-14T10:00:00Z","permission_mode":"default""#

    func testQwenFileAndCapabilities() {
        let adapter = AgentSource.qwen.adapter
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.qwen/settings.json")
        XCTAssertEqual(adapter.hookFile.format, .qwenSettings)
        XCTAssertEqual(adapter.hookFile.format.timeoutScale, 1000)
        XCTAssertTrue(adapter.hookFile.events.contains("PermissionRequest"))
        XCTAssertTrue(adapter.hookFile.waitsForApproval)
        XCTAssertTrue(adapter.hookFile.reportsWaiting)
        XCTAssertTrue(adapter.capabilities.contains(.approve))
        XCTAssertFalse(adapter.capabilities.contains(.answerQuestions))
    }

    func testQwenPermissionRequestAndReplies() throws {
        let request = try event(
            .qwen,
            #"{\#(qwenBase),"hook_event_name":"PermissionRequest","tool_name":"run_shell_command","tool_input":{"command":"npm test"},"permission_suggestions":[]}"#
        )
        XCTAssertEqual(request.kind, .permissionRequest)
        XCTAssertEqual(request.sessionID, "q-1")
        XCTAssertEqual(request.project, "shop")
        XCTAssertEqual(request.summary, "npm test")
        XCTAssertEqual(request.prompt, .tool)
        let allow = try reply(.qwen, allow: true)
        XCTAssertEqual(allow["hookSpecificOutput"]?["hookEventName"]?.stringValue, "PermissionRequest")
        XCTAssertEqual(allow["hookSpecificOutput"]?["decision"]?["behavior"]?.stringValue, "allow")
        let deny = try reply(.qwen, allow: false, reason: "not now")
        XCTAssertEqual(deny["hookSpecificOutput"]?["decision"]?["behavior"]?.stringValue, "deny")
        XCTAssertEqual(
            deny["hookSpecificOutput"]?["decision"]?["message"]?.stringValue, "Denied from the Wisp notch: not now")
        XCTAssertNil(AgentSource.qwen.adapter.reply(.answer(input: .object([:]), answers: [:])))
    }

    func testQwenLifecycle() throws {
        XCTAssertEqual(
            try event(.qwen, #"{\#(qwenBase),"hook_event_name":"SessionStart","source":"startup"}"#).kind, .sessionStart
        )
        let prompt = try event(.qwen, #"{\#(qwenBase),"hook_event_name":"UserPromptSubmit","prompt":"add tests"}"#)
        XCTAssertEqual(prompt.kind, .userPromptSubmit)
        XCTAssertEqual(prompt.promptText, "add tests")
        let note = try event(
            .qwen,
            #"{\#(qwenBase),"hook_event_name":"Notification","message":"Qwen needs your permission","notification_type":"permission_prompt"}"#
        )
        XCTAssertEqual(note.notificationType, "permission_prompt")
        XCTAssertEqual(
            try event(.qwen, #"{\#(qwenBase),"hook_event_name":"Stop","stop_hook_active":false}"#).kind, .stop)
    }

    func testQwenInstallWritesMillisecondTimeouts() throws {
        let file = AgentSource.qwen.adapter.hookFile
        let data = try HookInstaller.install(
            into: Data(#"{"model":{"name":"qwen3-coder"}}"#.utf8),
            command: "'/A/wisp-agent' --source qwen --timeout 1800",
            file: file, timeout: 1800)
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(root["model"]?["name"]?.stringValue, "qwen3-coder")
        let handler = root["hooks"]?["PermissionRequest"]?[0]?["hooks"]?[0]
        XCTAssertEqual(handler?["timeout"]?.intValue, 1_800_000)
        XCTAssertEqual(root["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["timeout"]?.intValue, 5000)
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: data, file: file), 1800)
    }

    // MARK: Qoder CLI (approve)

    func testQoderPermissionRequestAndReplies() throws {
        let adapter = AgentSource.qoder.adapter
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.qoder/settings.json")
        XCTAssertEqual(adapter.hookFile.format, .claudeSettings)
        XCTAssertTrue(adapter.capabilities.contains(.approve))
        XCTAssertTrue(adapter.hookFile.waitsForApproval)
        let request = try event(
            .qoder,
            #"{"session_id":"qo-1","cwd":"/Users/me/api","hook_event_name":"PermissionRequest","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"},"permission_suggestions":[]}"#
        )
        XCTAssertEqual(request.kind, .permissionRequest)
        XCTAssertEqual(request.summary, "rm -rf node_modules")
        XCTAssertEqual(request.prompt, .tool)
        XCTAssertEqual(
            try reply(.qoder, allow: true)["hookSpecificOutput"]?["decision"]?["behavior"]?.stringValue, "allow")
        let deny = try reply(.qoder, allow: false)
        XCTAssertEqual(deny["hookSpecificOutput"]?["hookEventName"]?.stringValue, "PermissionRequest")
        XCTAssertEqual(deny["hookSpecificOutput"]?["decision"]?["behavior"]?.stringValue, "deny")
        XCTAssertEqual(deny["hookSpecificOutput"]?["decision"]?["message"]?.stringValue, PermissionReply.defaultDenial)
    }

    // MARK: Droid (lifecycle)

    func testDroidFileAndEvents() throws {
        let adapter = AgentSource.droid.adapter
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.factory/hooks.json")
        XCTAssertEqual(adapter.hookFile.format, .factoryHooks)
        XCTAssertEqual(adapter.hookFile.seedPath, ".factory/settings.json")
        XCTAssertFalse(adapter.capabilities.contains(.approve), "PreToolUse runs on every tool call")
        XCTAssertFalse(adapter.hookFile.waitsForApproval)
        XCTAssertTrue(adapter.hookFile.reportsWaiting)
        XCTAssertTrue(adapter.hookFile.events.contains("PostToolUse"))
        XCTAssertEqual(adapter.hookFile.toolEvents, ["PreToolUse"])
        XCTAssertNil(adapter.reply(.allow(.tool, input: nil)))
        let note = try event(
            .droid,
            #"{"session_id":"d-1","transcript_path":"/Users/me/.factory/sessions/d-1.jsonl","cwd":"/Users/me/app","permission_mode":"auto-low","hook_event_name":"Notification","message":"Droid needs your permission to use Execute","notification_type":"permission_prompt"}"#
        )
        XCTAssertEqual(note.kind, .notification)
        XCTAssertEqual(note.project, "app")
        XCTAssertTrue(AgentSessions.waits(on: "permission_prompt", source: .droid))
        XCTAssertFalse(AgentSessions.waits(on: "permission_prompt", source: .qwen), "Qwen's prompt comes as a card")
        let tool = try event(
            .droid,
            #"{"session_id":"d-1","cwd":"/Users/me/app","hook_event_name":"PreToolUse","tool_name":"Execute","tool_input":{"command":"make test"}}"#
        )
        XCTAssertEqual(tool.kind, .preToolUse)
        XCTAssertEqual(tool.summary, "make test")
    }

    func testDroidInstallPutsEventsAtTheTopLevel() throws {
        let file = AgentSource.droid.adapter.hookFile
        let mine = #"{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"say done"}]}]}"#
        let data = try HookInstaller.install(
            into: Data(mine.utf8), command: "'/A/wisp-agent' --source droid", file: file)
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertNil(root["hooks"])
        XCTAssertEqual(
            root["SessionStart"]?[0]?["hooks"]?[0]?["command"]?.stringValue, "'/A/wisp-agent' --source droid")
        XCTAssertEqual(root["Stop"]?[0]?["hooks"]?[0]?["command"]?.stringValue, "say done")
        XCTAssertEqual(
            try HookInstaller.link(in: data, helper: "/A/wisp-agent", file: file), .this)
        let removed = try HookInstaller.remove(from: data, file: file)
        let back = try JSONDecoder().decode(JSONValue.self, from: removed)
        XCTAssertEqual(back, try JSONDecoder().decode(JSONValue.self, from: Data(mine.utf8)))
    }

    func testDroidSeedTakesTheSettingsHooks() throws {
        let settings = #"{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        let seed = try XCTUnwrap(HookInstaller.seed(fromSettings: Data(settings.utf8)))
        let root = try JSONDecoder().decode(JSONValue.self, from: seed)
        XCTAssertEqual(root["Stop"]?[0]?["hooks"]?[0]?["command"]?.stringValue, "say done")
        XCTAssertNil(root["model"])
        XCTAssertNil(HookInstaller.seed(fromSettings: Data(#"{"model":"x"}"#.utf8)))
        XCTAssertNil(HookInstaller.seed(fromSettings: Data("not json".utf8)))
    }

    // MARK: CodeBuddy (lifecycle)

    func testCodeBuddyFileAndEvents() throws {
        let adapter = AgentSource.codebuddy.adapter
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.codebuddy/settings.json")
        XCTAssertEqual(adapter.hookFile.format, .claudeSettings)
        XCTAssertFalse(adapter.capabilities.contains(.approve), "PermissionRequest's reply isn't documented")
        XCTAssertFalse(adapter.hookFile.events.contains("PermissionRequest"))
        XCTAssertTrue(adapter.hookFile.reportsWaiting)
        let start = try event(
            .codebuddy,
            #"{"session_id":"cb-1","transcript_path":"/t.jsonl","cwd":"/Users/me/web","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}"#
        )
        XCTAssertEqual(start.kind, .sessionStart)
        XCTAssertEqual(start.project, "web")
        XCTAssertTrue(AgentSessions.waits(on: "permission_prompt", source: .codebuddy))
    }

    // MARK: Kimi Code (lifecycle, TOML)

    func testKimiFileAndEvents() {
        let adapter = AgentSource.kimi.adapter
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.kimi-code/config.toml")
        XCTAssertEqual(adapter.hookFile.format, .kimiConfig)
        XCTAssertTrue(adapter.hookFile.permissionRequestObservesOnly)
        XCTAssertFalse(adapter.hookFile.waitsForApproval, "Kimi's PermissionRequest is observation only")
        XCTAssertTrue(adapter.hookFile.reportsWaiting)
        XCTAssertFalse(adapter.capabilities.contains(.approve))
        XCTAssertEqual(
            HookInstaller.command(helper: "/A/wisp-agent", file: adapter.hookFile, timeout: 1800),
            "'/A/wisp-agent' --source kimi")
    }

    func testKimiPermissionRequestIsNeedsYou() throws {
        let base =
            #""session_id":"session_abc","session_title":"Fix the login page","client_type":"kimi_code_cli","cwd":"/path/to/project""#
        let request = try event(
            .kimi,
            #"{\#(base),"hook_event_name":"PermissionRequest","tool_name":"Shell","tool_input":{"command":"rm -rf dist"}}"#
        )
        XCTAssertEqual(request.kind, .notification)
        XCTAssertEqual(request.notificationType, "permission_prompt")
        XCTAssertEqual(request.project, "project")
        XCTAssertTrue(AgentSessions.waits(on: "permission_prompt", source: .kimi))
        let result = try event(.kimi, #"{\#(base),"hook_event_name":"PermissionResult"}"#)
        XCTAssertEqual(result.kind, .postToolUse, "an answered prompt puts the session back to work")
        XCTAssertEqual(try event(.kimi, #"{\#(base),"hook_event_name":"Interrupt"}"#).kind, .interrupt)
        XCTAssertEqual(try event(.kimi, #"{\#(base),"hook_event_name":"Stop"}"#).kind, .stop)
        let tool = try event(
            .kimi, #"{\#(base),"hook_event_name":"PreToolUse","tool_input":{"command":"grep -r foo"}}"#)
        XCTAssertEqual(tool.kind, .preToolUse)
        XCTAssertEqual(tool.summary, "grep -r foo")
        XCTAssertNil(AgentSource.kimi.adapter.reply(.allow(.tool, input: nil)))
    }

    // MARK: Grok (lifecycle, camelCase)

    func testGrokFileAndCamelCaseFields() throws {
        let adapter = AgentSource.grok.adapter
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.grok/hooks/wisp.json")
        XCTAssertEqual(adapter.hookFile.format, .grokHooks)
        XCTAssertTrue(adapter.hookFile.format.ownedByWisp)
        XCTAssertFalse(adapter.capabilities.contains(.approve), "Grok has no permission request hook")
        let tool = try event(
            .grok,
            #"{"hookEventName":"PreToolUse","sessionId":"g-1","cwd":"/Users/me/game/src","workspaceRoot":"/Users/me/game","toolName":"Bash","toolInput":{"command":"cargo test"}}"#
        )
        XCTAssertEqual(tool.kind, .preToolUse)
        XCTAssertEqual(tool.sessionID, "g-1")
        XCTAssertEqual(tool.project, "game", "the workspace root names the session")
        XCTAssertEqual(tool.toolName, "Bash")
        XCTAssertEqual(tool.summary, "cargo test")
        let stop = try event(.grok, #"{"hookEventName":"Stop","sessionId":"g-1","cwd":"/Users/me/game"}"#)
        XCTAssertEqual(stop.kind, .stop)
    }

    func testGrokRunsClaudeHooksToo() {
        XCTAssertTrue(GrokHooks.isImported(environment: ["GROK_HOOK_EVENT": "Stop"], source: .claude))
        XCTAssertFalse(GrokHooks.isImported(environment: ["GROK_HOOK_EVENT": "Stop"], source: .grok))
        XCTAssertFalse(GrokHooks.isImported(environment: [:], source: .claude))
    }

    func testGrokInstallAndRemoveLeavesNothing() throws {
        let file = AgentSource.grok.adapter.hookFile
        let data = try HookInstaller.install(into: Data(), command: "'/A/wisp-agent' --source grok", file: file)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/A/wisp-agent", file: file), .this)
        let removed = try HookInstaller.remove(from: data, file: file)
        XCTAssertTrue(try HookInstaller.isLeftEmpty(removed, file: file))
    }

    // MARK: Mistral Vibe (lifecycle, TOML)

    func testVibeEvents() throws {
        let adapter = AgentSource.vibe.adapter
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.vibe/hooks.toml")
        XCTAssertEqual(adapter.hookFile.format, .vibeHooks)
        XCTAssertEqual(adapter.hookFile.events, ["pre_tool", "post_tool", "post_agent"])
        XCTAssertFalse(adapter.capabilities.contains(.approve))
        let base = #""session_id":"v-1","parent_session_id":null,"transcript_path":"/t.jsonl","cwd":"/Users/me/ml""#
        let pre = try event(
            .vibe,
            #"{\#(base),"hook_event_name":"pre_tool","tool_name":"bash","tool_call_id":"call_1","tool_input":{"command":"pytest"}}"#
        )
        XCTAssertEqual(pre.kind, .preToolUse)
        XCTAssertEqual(pre.toolUseID, "call_1")
        XCTAssertEqual(pre.summary, "pytest")
        let post = try event(
            .vibe,
            #"{\#(base),"hook_event_name":"post_tool","tool_name":"bash","tool_call_id":"call_1","tool_input":{"command":"pytest"},"tool_status":"success","duration_ms":120}"#
        )
        XCTAssertEqual(post.kind, .postToolUse)
        XCTAssertEqual(post.toolUseID, "call_1")
        let done = try event(.vibe, #"{\#(base),"hook_event_name":"post_agent","agent_name":"default"}"#)
        XCTAssertEqual(done.kind, .stop)
        XCTAssertEqual(done.project, "ml")
    }

    func testToolHooksAreSentWithoutWaiting() {
        let pre = Data(#"{"hook_event_name":"pre_tool","session_id":"v"}"#.utf8)
        XCTAssertEqual(AgentProtocol.kind(forHook: pre, source: .vibe), .tool)
        let permission = Data(#"{"hook_event_name":"PermissionRequest","session_id":"k"}"#.utf8)
        XCTAssertEqual(AgentProtocol.kind(forHook: permission, source: .kimi), .hook)
    }
}
