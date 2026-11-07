import XCTest

@testable import WispCore

/// Hook payloads copied from Cursor's hooks reference (cursor.com/docs/agent/hooks, checked on
/// 2026-11-07): the common fields every hook gets plus each event's own, with the documented
/// example values where there are any. The installed cursor-agent (2025.09.12) predates hooks,
/// so none of these came from a live run.
final class CursorAdapterTests: XCTestCase {
    private let adapter = AgentSource.cursor.adapter

    private func event(_ text: String) throws -> AgentEvent {
        try XCTUnwrap(adapter.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), terminal: nil))
    }

    private let base =
        #""conversation_id":"c-1","generation_id":"g-1","model":"claude-opus-4-7-thinking-max","cursor_version":"3.4.0","workspace_roots":["/Users/me/site"],"user_email":null,"transcript_path":null"#

    func testNameFileAndCapabilities() {
        XCTAssertEqual(adapter.displayName, "Cursor")
        XCTAssertEqual(adapter.symbol, "cursorarrow")
        XCTAssertEqual(adapter.fallbackProject, "Cursor")
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.cursor/hooks.json")
        XCTAssertEqual(adapter.hookFile.format, .cursorHooks)
        XCTAssertEqual(adapter.hookFile.helperArguments, " --source cursor")
        XCTAssertFalse(adapter.hookFile.statusLine)
        XCTAssertFalse(adapter.capabilities.contains(.approve), "only a hook's deny is enforced")
        XCTAssertFalse(adapter.capabilities.contains(.answerQuestions))
        XCTAssertFalse(adapter.capabilities.contains(.rules))
        XCTAssertFalse(adapter.capabilities.contains(.limits))
        XCTAssertTrue(adapter.capabilities.contains(.toolActivity))
        XCTAssertEqual(AgentSource(rawValue: "cursor"), .cursor)
    }

    /// No permission hook (preToolUse, beforeShellExecution, beforeMCPExecution, beforeReadFile,
    /// subagentStart): Cursor blocks the action when one of those prints something it can't read.
    func testHookEventsLeaveOutPermissionHooks() {
        let file = adapter.hookFile
        XCTAssertEqual(file.events, ["sessionStart", "beforeSubmitPrompt", "stop", "sessionEnd", "preCompact"])
        XCTAssertEqual(file.toolEvents, ["postToolUse"])
        XCTAssertTrue(file.backgroundEvents.isEmpty)
        XCTAssertFalse(file.waitsForApproval)
        XCTAssertFalse(file.reportsWaiting, "Cursor has no event for a prompt waiting on you")
        XCTAssertTrue(AgentSource.gemini.adapter.hookFile.reportsWaiting)
        XCTAssertTrue(AgentSource.claude.adapter.hookFile.reportsWaiting)
        let permissionHooks: Set = [
            "preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "subagentStart",
        ]
        XCTAssertTrue(permissionHooks.isDisjoint(with: file.events + file.toolEvents))
    }

    func testSessionStartAndEnd() throws {
        let start = try event(
            #"{\#(base),"hook_event_name":"sessionStart","session_id":"c-1","is_background_agent":false,"composer_mode":"agent"}"#
        )
        XCTAssertEqual(start.kind, .sessionStart)
        XCTAssertEqual(start.source, .cursor)
        XCTAssertEqual(start.sessionID, "c-1")
        XCTAssertEqual(start.project, "site")
        XCTAssertEqual(start.cwd, "/Users/me/site")
        let end = try event(
            #"{\#(base),"hook_event_name":"sessionEnd","session_id":"c-1","reason":"completed","duration_ms":45000,"is_background_agent":false,"final_status":"completed"}"#
        )
        XCTAssertEqual(end.kind, .sessionEnd)
        XCTAssertEqual(end.sessionID, "c-1")
    }

    /// Only sessionStart and sessionEnd carry `session_id`; every event has `conversation_id`.
    func testTheConversationIsTheSession() throws {
        let stop = try event(#"{\#(base),"hook_event_name":"stop","status":"completed","loop_count":0}"#)
        XCTAssertEqual(stop.sessionID, "c-1")
    }

    func testPromptAndStop() throws {
        let prompt = try event(
            #"{\#(base),"hook_event_name":"beforeSubmitPrompt","prompt":"fix the login bug","attachments":[{"type":"file","file_path":"/Users/me/site/login.ts"}]}"#
        )
        XCTAssertEqual(prompt.kind, .userPromptSubmit)
        XCTAssertEqual(prompt.summary, "", "the prompt never becomes a summary")
        XCTAssertNil(prompt.message)
        for status in ["completed", "aborted", "error"] {
            let stop = try event(#"{\#(base),"hook_event_name":"stop","status":"\#(status)","loop_count":0}"#)
            XCTAssertEqual(stop.kind, .stop)
        }
    }

    func testPreCompact() throws {
        let compact = try event(
            #"{\#(base),"hook_event_name":"preCompact","trigger":"auto","context_usage_percent":85,"context_tokens":120000,"context_window_size":128000,"message_count":45,"messages_to_compact":30,"is_first_compaction":true}"#
        )
        XCTAssertEqual(compact.kind, .preCompact)
    }

    private let postShell =
        #""hook_event_name":"postToolUse","tool_name":"Shell","tool_input":{"command":"npm test"},"tool_output":"{\"exitCode\":0,\"stdout\":\"All tests passed\"}","tool_use_id":"abc123","cwd":"/Users/me/site/web","duration":5432"#

    func testPostToolUseIsToolActivity() throws {
        let after = try event("{\(base),\(postShell)}")
        XCTAssertEqual(after.kind, .postToolUse)
        XCTAssertEqual(after.toolName, "Shell")
        XCTAssertEqual(after.toolUseID, "abc123")
        XCTAssertEqual(after.summary, "npm test")
        XCTAssertEqual(after.project, "site", "the workspace names the session, not the tool's folder")
        XCTAssertEqual(
            AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"postToolUse"}"#.utf8), source: .cursor), .tool)
        XCTAssertEqual(
            AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"stop"}"#.utf8), source: .cursor), .hook)
    }

    func testAWorkspacelessEventUsesTheToolsFolder() throws {
        let after = try event(
            #"{"conversation_id":"c-2","workspace_roots":[],\#(postShell)}"#)
        XCTAssertEqual(after.project, "web")
    }

    /// Cursor only reports a tool once it's done, so the pill shows it as the last tool.
    func testAFinishedToolShowsInThePill() throws {
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"beforeSubmitPrompt","prompt":"x"}"#), at: now)
        sessions.apply(try event("{\(base),\(postShell)}"), at: now.addingTimeInterval(6))
        let session = try XCTUnwrap(sessions.session("c-1"))
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(session.runningTools.isEmpty)
        XCTAssertEqual(session.toolCount, 1)
        XCTAssertEqual(session.pillTool(now: now.addingTimeInterval(7))?.label, "Running npm test")
        XCTAssertNil(session.pillTool(now: now.addingTimeInterval(6 + AgentSession.toolLinger)))
        sessions.apply(
            try event(#"{\#(base),"hook_event_name":"stop","status":"completed","loop_count":0}"#),
            at: now.addingTimeInterval(8))
        XCTAssertEqual(sessions.session("c-1")?.state, .finished)
    }

    func testOtherEventsAreIgnored() throws {
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"afterAgentResponse","text":"Done."}"#).kind, .other)
        XCTAssertEqual(
            try event(#"{\#(base),"hook_event_name":"beforeShellExecution","command":"ls","cwd":"/"}"#).kind, .other)
        // Claude Code's names mean nothing from Cursor.
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"Stop"}"#).kind, .other)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"PermissionRequest"}"#).kind, .other)
    }

    func testMonitorOnlyNeverReplies() {
        XCTAssertNil(adapter.reply(.decide(.tool, allow: true, input: nil)))
        XCTAssertNil(adapter.reply(.deny(.tool, reason: "no")))
        XCTAssertEqual(adapter.prompt(tool: "ExitPlanMode"), .tool)
    }

    /// Cursor reads every hook's stdout as JSON; beforeSubmitPrompt's documented output is `continue`.
    func testSilentRepliesSayCarryOn() {
        func reply(_ text: String, _ source: AgentSource) -> String? {
            AgentProtocol.silentReply(forHook: Data(text.utf8), source: source)
        }
        XCTAssertEqual(
            reply(#"{\#(base),"hook_event_name":"beforeSubmitPrompt","prompt":"x"}"#, .cursor), #"{"continue":true}"#)
        XCTAssertEqual(reply(#"{\#(base),"hook_event_name":"stop","status":"completed"}"#, .cursor), "{}")
        XCTAssertEqual(reply("{\(base),\(postShell)}", .cursor), "{}")
        XCTAssertEqual(reply("not json", .cursor), "{}", "a payload the helper can't read still gets an answer")
        XCTAssertEqual(adapter.hookFile.format.silentReply(event: "beforeSubmitPrompt"), #"{"continue":true}"#)
        XCTAssertEqual(adapter.hookFile.format.silentReply(event: "sessionStart"), "{}")
        for other in [AgentSource.claude, .codex, .gemini] {
            XCTAssertNil(other.adapter.hookFile.format.silentReply(event: "Stop"))
            XCTAssertNil(reply(#"{"session_id":"s","hook_event_name":"Stop"}"#, other))
        }
    }

    /// Cursor runs Claude Code's hooks too (Third-Party Imports); Wisp's Claude Code hooks then
    /// get Cursor's payload, recognised by `cursor_version`, and drop it with Cursor's reply.
    func testClaudeHooksRunByCursorAreDropped() {
        let prompt = Data(#"{\#(base),"hook_event_name":"UserPromptSubmit","prompt":"x"}"#.utf8)
        let preTool = Data(
            #"{\#(base),"hook_event_name":"PreToolUse","tool_name":"Shell","tool_input":{"command":"ls"},"tool_use_id":"t1","cwd":"/Users/me/site"}"#
                .utf8)
        let cursorStyle = Data(#"{\#(base),"hook_event_name":"preToolUse","tool_name":"Shell"}"#.utf8)
        for payload in [prompt, preTool, cursorStyle] {
            XCTAssertTrue(CursorHooks.isImported(payload, source: .claude))
        }
        XCTAssertEqual(AgentProtocol.silentReply(forHook: prompt, source: .claude), #"{"continue":true}"#)
        XCTAssertEqual(AgentProtocol.silentReply(forHook: preTool, source: .claude), "{}")
        XCTAssertFalse(CursorHooks.isImported(preTool, source: .cursor), "Cursor's own hooks are read")
        let claudeCode = Data(#"{"session_id":"s","cwd":"/a","hook_event_name":"PreToolUse","tool_name":"Bash"}"#.utf8)
        XCTAssertFalse(CursorHooks.isImported(claudeCode, source: .claude))
        XCTAssertNil(AgentProtocol.silentReply(forHook: claudeCode, source: .claude))
        XCTAssertFalse(CursorHooks.isImported(Data("not json".utf8), source: .claude))
    }

    func testCursorToolNamesGetLabels() {
        func label(_ tool: String, _ input: ToolInput) -> String {
            ToolLabel.describe(tool: tool, input: input, hidden: false).label
        }
        XCTAssertEqual(label("Shell", ToolInput(command: "npm test")), "Running npm test")
        XCTAssertEqual(
            ToolLabel.describe(tool: "Shell", input: ToolInput(command: "npm test"), hidden: true).label,
            "Running a command")
        XCTAssertEqual(label("Delete", ToolInput(filePath: "/a/old.md")), "Editing old.md")
        XCTAssertEqual(label("MCP:create_issue", ToolInput()), "MCP: create_issue")
        XCTAssertEqual(
            ToolLabel.describe(tool: "MCP:create_issue", input: ToolInput(), hidden: false).symbol,
            "puzzlepiece.extension")
    }
}

final class CursorHookFileTests: XCTestCase {
    private let file = AgentSource.cursor.adapter.hookFile
    private let command = "'/A/wisp-agent' --source cursor"

    private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    /// Cursor's hooks are flat handler lists under a versioned file, not matcher groups.
    func testWritesFlatHandlersAndAVersion() throws {
        let out = try json(HookInstaller.install(into: Data(), command: command, file: file, tools: true))
        XCTAssertEqual(out["version"], .number(1))
        XCTAssertEqual(out["hooks"]?["stop"]?[0]?["command"], .string(command))
        XCTAssertEqual(out["hooks"]?["stop"]?[0]?["timeout"], .number(5))
        XCTAssertNil(out["hooks"]?["stop"]?[0]?["matcher"])
        XCTAssertNil(out["hooks"]?["stop"]?[0]?["hooks"])
        XCTAssertNil(out["hooks"]?["stop"]?[0]?["async"])
        XCTAssertEqual(out["hooks"]?["postToolUse"]?[0]?["command"], .string(command))
        XCTAssertNil(out["hooks"]?["preToolUse"])
    }

    func testLinkToolsAndReinstall() throws {
        let data = try HookInstaller.install(into: Data(), command: command, file: file)
        XCTAssertNil(try json(data)["hooks"]?["postToolUse"])
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: data, file: file))
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/A/wisp-agent", file: file), .this)
        let withTools = try HookInstaller.install(into: data, command: command, file: file, tools: true)
        XCTAssertTrue(try HookInstaller.toolsInstalled(in: withTools, file: file))
        XCTAssertEqual(try HookInstaller.link(in: withTools, helper: "/A/wisp-agent", file: file), .this)
        XCTAssertEqual(try json(withTools)["hooks"]?["stop"]?.count, 1, "reinstalling doesn't duplicate")
        XCTAssertEqual(
            try HookInstaller.link(in: withTools, helper: "/B/wisp-agent", file: file), .other)
        XCTAssertEqual(
            try HookInstaller.link(in: Data(#"{"version":1}"#.utf8), helper: "/A/wisp-agent", file: file), .none)
    }

    func testTheCommandNeverWaitsBecauseNothingAsksWisp() throws {
        XCTAssertEqual(HookInstaller.command(helper: "/A/wisp-agent", file: file, timeout: 600), command)
        let data = try HookInstaller.install(into: Data(), command: command, file: file)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/A/wisp-agent", file: file, timeout: 600), .this)
    }

    func testKeepsTheUsersVersionAndHooks() throws {
        let settings = Data(
            #"{"version":2,"hooks":{"beforeShellExecution":[{"command":"./hooks/audit.sh","matcher":"git","failClosed":true}],"stop":[{"command":"./hooks/notify.sh","timeout":10}]}}"#
                .utf8)
        let installed = try HookInstaller.install(into: settings, command: command, file: file, tools: true)
        let out = try json(installed)
        XCTAssertEqual(out["version"], .number(2))
        XCTAssertEqual(out["hooks"]?["beforeShellExecution"]?[0]?["command"], .string("./hooks/audit.sh"))
        XCTAssertEqual(out["hooks"]?["stop"]?[0]?["command"], .string("./hooks/notify.sh"))
        XCTAssertEqual(out["hooks"]?["stop"]?[1]?["command"], .string(command))
        XCTAssertTrue(try HookInstaller.isInstalled(in: installed))
        let removed = try json(HookInstaller.remove(from: installed))
        XCTAssertEqual(removed["version"], .number(2))
        XCTAssertEqual(removed["hooks"]?["stop"]?.count, 1)
        XCTAssertEqual(removed["hooks"]?["stop"]?[0]?["command"], .string("./hooks/notify.sh"))
        XCTAssertNil(removed["hooks"]?["sessionStart"])
        XCTAssertEqual(removed["hooks"]?["beforeShellExecution"]?[0]?["failClosed"], .bool(true))
    }

    /// The hook file lives in a temporary home; nothing touches the real ~/.cursor.
    func testInstallsUnderAGivenHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let url = file.url(home: home)
        XCTAssertEqual(url.path, home.path + "/.cursor/hooks.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HookInstaller.install(into: Data(), command: command, file: file).write(to: url)
        XCTAssertEqual(try HookInstaller.link(in: Data(contentsOf: url), helper: "/A/wisp-agent", file: file), .this)
    }
}
