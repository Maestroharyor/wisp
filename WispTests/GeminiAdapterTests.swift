import XCTest

@testable import WispCore

/// Hook payloads built from Gemini CLI's hooks reference and its `hooks/types.ts` (field names
/// and event names, checked against v0.67.0 docs on 2026-11-07) with made-up values. Gemini
/// CLI wasn't installed, so none of these came from a live run.
final class GeminiAdapterTests: XCTestCase {
    private let adapter = AgentSource.gemini.adapter

    private func event(_ text: String) throws -> AgentEvent {
        try XCTUnwrap(adapter.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), terminal: nil))
    }

    private let base =
        #""session_id":"g-1","transcript_path":"/Users/me/.gemini/tmp/abc/chats/session-1.json","cwd":"/Users/me/site","timestamp":"2026-11-07T10:00:00.000Z""#

    func testNameFileAndCapabilities() {
        XCTAssertEqual(adapter.displayName, "Gemini CLI")
        XCTAssertEqual(adapter.fallbackProject, "Gemini")
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.gemini/settings.json")
        XCTAssertEqual(adapter.hookFile.format, .geminiSettings)
        XCTAssertEqual(adapter.hookFile.helperArguments, " --source gemini")
        XCTAssertFalse(adapter.hookFile.statusLine)
        XCTAssertFalse(adapter.capabilities.contains(.approve), "BeforeTool's allow can't skip Gemini's own prompt")
        XCTAssertFalse(adapter.capabilities.contains(.answerQuestions))
        XCTAssertFalse(adapter.capabilities.contains(.rules))
        XCTAssertFalse(adapter.capabilities.contains(.limits))
        XCTAssertTrue(adapter.capabilities.contains(.toolActivity))
    }

    func testHookEvents() {
        let file = adapter.hookFile
        XCTAssertEqual(
            file.events,
            ["SessionStart", "BeforeAgent", "Notification", "AfterTool", "AfterAgent", "SessionEnd", "PreCompress"])
        XCTAssertEqual(file.toolEvents, ["BeforeTool"])
        XCTAssertTrue(file.backgroundEvents.isEmpty, "Gemini CLI has no async hooks")
        XCTAssertFalse(file.waitsForApproval)
        XCTAssertTrue(AgentSource.claude.adapter.hookFile.waitsForApproval)
        XCTAssertTrue(AgentSource.codex.adapter.hookFile.waitsForApproval)
    }

    func testSessionStartAndEnd() throws {
        let start = try event(#"{\#(base),"hook_event_name":"SessionStart","source":"startup"}"#)
        XCTAssertEqual(start.kind, .sessionStart)
        XCTAssertEqual(start.source, .gemini)
        XCTAssertEqual(start.sessionID, "g-1")
        XCTAssertEqual(start.project, "site")
        XCTAssertEqual(start.startSource, "startup")
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"SessionStart","source":"resume"}"#).isResume, true)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"SessionEnd","reason":"exit"}"#).kind, .sessionEnd)
    }

    func testAgentTurnsMapToPromptAndStop() throws {
        let prompt = try event(#"{\#(base),"hook_event_name":"BeforeAgent","prompt":"fix the login bug"}"#)
        XCTAssertEqual(prompt.kind, .userPromptSubmit)
        XCTAssertEqual(prompt.summary, "", "the prompt never becomes a summary")
        XCTAssertNil(prompt.message)
        let stop = try event(
            #"{\#(base),"hook_event_name":"AfterAgent","prompt":"fix it","prompt_response":"Done.","stop_hook_active":false}"#
        )
        XCTAssertEqual(stop.kind, .stop)
        XCTAssertNil(stop.message)
    }

    func testCompressionIsPreCompact() throws {
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"PreCompress","trigger":"auto"}"#).kind, .preCompact)
    }

    func testToolHooksMapToToolActivity() throws {
        let before = try event(
            #"{\#(base),"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"npm test","description":"Run the tests"}}"#
        )
        XCTAssertEqual(before.kind, .preToolUse)
        XCTAssertEqual(before.toolName, "run_shell_command")
        XCTAssertEqual(before.summary, "npm test")
        XCTAssertNil(before.toolUseID)
        let after = try event(
            #"{\#(base),"hook_event_name":"AfterTool","tool_name":"replace","tool_input":{"file_path":"/Users/me/site/app.js","old_string":"a","new_string":"b"},"tool_response":{"llmContent":"ok","returnDisplay":"ok"}}"#
        )
        XCTAssertEqual(after.kind, .postToolUse)
        XCTAssertEqual(after.summary, "/Users/me/site/app.js")
    }

    func testToolHooksAreSentAsToolActivity() {
        let before = Data(#"{"hook_event_name":"BeforeTool"}"#.utf8)
        XCTAssertEqual(AgentProtocol.kind(forHook: before, source: .gemini), .tool)
        XCTAssertEqual(
            AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"AfterTool"}"#.utf8), source: .gemini), .tool)
        XCTAssertEqual(
            AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"AfterAgent"}"#.utf8), source: .gemini), .hook)
    }

    func testAToolConfirmationNeedsYou() throws {
        let notice = try event(
            #"{\#(base),"hook_event_name":"Notification","notification_type":"ToolPermission","message":"Tool needs confirmation","details":{"type":"exec"}}"#
        )
        XCTAssertEqual(notice.kind, .notification)
        XCTAssertEqual(notice.notificationType, "ToolPermission")
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"BeforeAgent","prompt":"x"}"#), at: now)
        XCTAssertEqual(sessions.session("g-1")?.state, .running)
        sessions.apply(notice, at: now.addingTimeInterval(1))
        XCTAssertEqual(sessions.session("g-1")?.state, .waiting)
        sessions.apply(
            try event(#"{\#(base),"hook_event_name":"AfterAgent","prompt":"x","prompt_response":"y"}"#), at: now)
        XCTAssertEqual(sessions.session("g-1")?.state, .finished)
    }

    private let toolPermission =
        #""hook_event_name":"Notification","notification_type":"ToolPermission","message":"Confirm","details":{}"#
    private let afterTool =
        #""hook_event_name":"AfterTool","tool_name":"run_shell_command","tool_input":{"command":"npm test"},"tool_response":{"llmContent":"ok"}"#

    /// With tool activity on: BeforeTool, then Gemini asks, then the tool runs once answered.
    func testAnsweringInTheTerminalGoesBackToWorkWithToolActivity() throws {
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"BeforeAgent","prompt":"x"}"#), at: now)
        sessions.apply(
            try event(
                #"{\#(base),"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"npm test"}}"#
            ), at: now.addingTimeInterval(1))
        XCTAssertEqual(sessions.session("g-1")?.runningTools.count, 1)
        sessions.apply(try event("{\(base),\(toolPermission)}"), at: now.addingTimeInterval(2))
        XCTAssertEqual(sessions.session("g-1")?.state, .waiting)
        sessions.apply(try event("{\(base),\(afterTool)}"), at: now.addingTimeInterval(5))
        XCTAssertEqual(sessions.session("g-1")?.state, .running)
        XCTAssertEqual(sessions.session("g-1")?.runningTools.count, 0)
    }

    /// The default install has no BeforeTool, but AfterTool is always there.
    func testAnsweringInTheTerminalGoesBackToWorkByDefault() throws {
        XCTAssertTrue(adapter.hookFile.events.contains("AfterTool"))
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"BeforeAgent","prompt":"x"}"#), at: now)
        sessions.apply(try event("{\(base),\(toolPermission)}"), at: now.addingTimeInterval(1))
        XCTAssertEqual(sessions.session("g-1")?.state, .waiting)
        sessions.apply(try event("{\(base),\(afterTool)}"), at: now.addingTimeInterval(4))
        XCTAssertEqual(sessions.session("g-1")?.state, .running)
        XCTAssertEqual(sessions.session("g-1")?.runningTools.count, 0)
    }

    /// A rejected confirmation runs no tool; the next prompt (or the end of the turn) moves on.
    func testARejectedConfirmationWaitsUntilTheNextPrompt() throws {
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"BeforeAgent","prompt":"x"}"#), at: now)
        sessions.apply(try event("{\(base),\(toolPermission)}"), at: now.addingTimeInterval(1))
        sessions.apply(
            try event(#"{\#(base),"hook_event_name":"BeforeAgent","prompt":"y"}"#), at: now.addingTimeInterval(9))
        XCTAssertEqual(sessions.session("g-1")?.state, .running)
    }

    func testOtherEventsAreIgnored() throws {
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"BeforeModel","llm_request":{}}"#).kind, .other)
        // Claude Code's names mean nothing from Gemini CLI.
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"Stop"}"#).kind, .other)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"PermissionRequest"}"#).kind, .other)
    }

    func testMonitorOnlyNeverReplies() {
        XCTAssertNil(adapter.reply(.decide(.tool, allow: true, input: nil)))
        XCTAssertNil(adapter.reply(.deny(.tool, reason: "no")))
        XCTAssertNil(adapter.reply(.answer(input: .object([:]), answers: [:])))
        XCTAssertEqual(adapter.prompt(tool: "ExitPlanMode"), .tool)
    }

    func testGeminiToolNamesGetLabels() {
        func label(_ tool: String, _ input: ToolInput) -> String {
            ToolLabel.describe(tool: tool, input: input, hidden: false).label
        }
        XCTAssertEqual(label("run_shell_command", ToolInput(command: "npm test")), "Running npm test")
        XCTAssertEqual(label("replace", ToolInput(filePath: "/a/b/app.js")), "Editing app.js")
        XCTAssertEqual(label("write_file", ToolInput(filePath: "/a/new.md")), "Editing new.md")
        XCTAssertEqual(label("read_file", ToolInput(filePath: "/a/c.swift")), "Reading c.swift")
        XCTAssertEqual(label("grep_search", ToolInput(pattern: "TODO")), "Searching TODO")
        XCTAssertEqual(label("glob", ToolInput(pattern: "*.ts")), "Searching *.ts")
        XCTAssertEqual(label("google_web_search", ToolInput(query: "x")), "Searching the web")
        XCTAssertEqual(label("web_fetch", ToolInput()), "Fetching a page")
    }
}

final class GeminiHookFileTests: XCTestCase {
    private let file = AgentSource.gemini.adapter.hookFile
    private let command = "'/A/wisp-agent' --source gemini"

    private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    func testTimeoutsAreInMilliseconds() throws {
        let out = try json(HookInstaller.install(into: Data("{}".utf8), command: command, file: file, tools: true))
        XCTAssertEqual(out["hooks"]?["AfterAgent"]?[0]?["hooks"]?[0]?["timeout"], .number(5000))
        XCTAssertEqual(out["hooks"]?["BeforeTool"]?[0]?["hooks"]?[0]?["timeout"], .number(5000))
        XCTAssertEqual(out["hooks"]?["BeforeTool"]?[0]?["matcher"], .string(""))
        XCTAssertNil(out["hooks"]?["BeforeTool"]?[0]?["hooks"]?[0]?["async"])
        XCTAssertNil(out["hooks"]?["PermissionRequest"])
        XCTAssertEqual(out["hooks"]?["SessionStart"]?[0]?["hooks"]?[0]?["command"], .string(command))
        XCTAssertEqual(out["hooks"]?["SessionStart"]?[0]?["hooks"]?[0]?["type"], .string("command"))
    }

    func testTheDefaultInstallHasAfterToolButNotToolActivity() throws {
        let data = try HookInstaller.install(into: Data("{}".utf8), command: command, file: file)
        let out = try json(data)
        XCTAssertEqual(out["hooks"]?["AfterTool"]?[0]?["hooks"]?[0]?["timeout"], .number(5000))
        XCTAssertNil(out["hooks"]?["BeforeTool"])
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: data, file: file))
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/A/wisp-agent", file: file), .this)
        let withTools = try HookInstaller.install(into: data, command: command, file: file, tools: true)
        XCTAssertEqual(try HookInstaller.link(in: withTools, helper: "/A/wisp-agent", file: file), .this)
        XCTAssertEqual(try json(withTools)["hooks"]?["AfterTool"]?.count, 1, "reinstalling doesn't duplicate")
    }

    func testClaudeTimeoutsStayInSeconds() throws {
        let out = try json(
            HookInstaller.install(
                into: Data("{}".utf8), command: "'/A/wisp-agent'", file: AgentSource.claude.adapter.hookFile))
        XCTAssertEqual(out["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["timeout"], .number(5))
        XCTAssertEqual(out["hooks"]?["PermissionRequest"]?[0]?["hooks"]?[0]?["timeout"], .number(120))
    }

    func testTheCommandNeverWaitsBecauseNothingAsksWisp() {
        XCTAssertEqual(HookInstaller.command(helper: "/A/wisp-agent", file: file, timeout: 600), command)
    }

    func testALongerApprovalWaitLeavesGeminiCurrent() throws {
        let data = try HookInstaller.install(
            into: Data("{}".utf8), command: HookInstaller.command(helper: "/A/wisp-agent", file: file), file: file)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/A/wisp-agent", file: file, timeout: 600), .this)
        XCTAssertNil(try HookInstaller.installedApprovalTimeout(in: data))
    }

    func testKeepsTheUsersSettingsAndHooks() throws {
        let settings = Data(
            #"{"model":{"name":"gemini-2.5-pro"},"hooksConfig":{"enabled":true},"hooks":{"BeforeTool":[{"matcher":"write_file","hooks":[{"name":"check","type":"command","command":"./check.sh","timeout":3000}]}]}}"#
                .utf8)
        let installed = try HookInstaller.install(into: settings, command: command, file: file, tools: true)
        let out = try json(installed)
        XCTAssertEqual(out["model"]?["name"], .string("gemini-2.5-pro"))
        XCTAssertEqual(out["hooksConfig"]?["enabled"], .bool(true))
        XCTAssertEqual(out["hooks"]?["BeforeTool"]?[0]?["hooks"]?[0]?["command"], .string("./check.sh"))
        XCTAssertEqual(out["hooks"]?["BeforeTool"]?[1]?["hooks"]?[0]?["command"], .string(command))
        XCTAssertTrue(try HookInstaller.toolsInstalled(in: installed, file: file))
        let removed = try json(HookInstaller.remove(from: installed))
        XCTAssertEqual(removed["hooks"]?["BeforeTool"]?[0]?["hooks"]?[0]?["command"], .string("./check.sh"))
        XCTAssertNil(removed["hooks"]?["BeforeTool"]?[1])
        XCTAssertNil(removed["hooks"]?["SessionStart"])
    }

    /// The settings file lives in a temporary home; nothing touches the real ~/.gemini.
    func testInstallsUnderAGivenHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let url = file.url(home: home)
        XCTAssertEqual(url.path, home.path + "/.gemini/settings.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HookInstaller.install(into: Data(), command: command, file: file).write(to: url)
        XCTAssertEqual(try HookInstaller.link(in: Data(contentsOf: url), helper: "/A/wisp-agent", file: file), .this)
    }
}
