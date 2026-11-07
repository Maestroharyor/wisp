import XCTest

@testable import WispCore

/// Hook payloads in the shape Copilot CLI sends to hooks configured under PascalCase event names
/// (snake_case fields and `hook_event_name`, as in VS Code and Claude Code), with made-up values.
/// Field and event names follow GitHub's CLI hooks reference (docs.github.com, checked
/// 2026-11-07) and the strings in the Copilot CLI 1.0.107 package; the camelCase forms are the
/// reference's own. Copilot CLI wasn't installed, so none of these came from a live run.
final class CopilotAdapterTests: XCTestCase {
    private let adapter = AgentSource.copilot.adapter

    private func event(_ text: String) throws -> AgentEvent {
        try XCTUnwrap(adapter.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), terminal: nil))
    }

    private let base = #""session_id":"c-1","timestamp":"2026-11-07T10:00:00.000Z","cwd":"/Users/me/site""#

    func testNameFileAndCapabilities() {
        XCTAssertEqual(adapter.displayName, "Copilot CLI")
        XCTAssertEqual(adapter.fallbackProject, "Copilot")
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.copilot/hooks/wisp.json")
        XCTAssertEqual(adapter.hookFile.format, .copilotHooks)
        XCTAssertEqual(adapter.hookFile.helperArguments, " --source copilot")
        XCTAssertFalse(adapter.hookFile.statusLine)
        XCTAssertFalse(
            adapter.capabilities.contains(.approve), "PermissionRequest runs before Copilot's rules and approvals")
        XCTAssertFalse(adapter.capabilities.contains(.answerQuestions))
        XCTAssertFalse(adapter.capabilities.contains(.rules))
        XCTAssertFalse(adapter.capabilities.contains(.limits))
        XCTAssertFalse(adapter.capabilities.contains(.compaction))
        XCTAssertTrue(adapter.capabilities.contains(.toolActivity))
    }

    func testHookEvents() {
        let file = adapter.hookFile
        XCTAssertEqual(
            file.events,
            [
                "SessionStart", "UserPromptSubmit", "Notification", "PostToolUse", "PostToolUseFailure", "Stop",
                "SessionEnd", "PreCompact",
            ])
        XCTAssertEqual(file.toolEvents, ["PreToolUse"])
        XCTAssertTrue(file.backgroundEvents.isEmpty, "Copilot CLI documents no async hooks")
        XCTAssertFalse(file.waitsForApproval)
    }

    func testSessionStartAndEnd() throws {
        let start = try event(#"{\#(base),"hook_event_name":"SessionStart","source":"startup"}"#)
        XCTAssertEqual(start.kind, .sessionStart)
        XCTAssertEqual(start.source, .copilot)
        XCTAssertEqual(start.sessionID, "c-1")
        XCTAssertEqual(start.project, "site")
        XCTAssertEqual(start.startSource, "startup")
        XCTAssertTrue(try event(#"{\#(base),"hook_event_name":"SessionStart","source":"resume"}"#).isResume)
        XCTAssertEqual(
            try event(#"{\#(base),"hook_event_name":"SessionEnd","reason":"user_exit"}"#).kind, .sessionEnd)
    }

    func testPromptAndStop() throws {
        let prompt = try event(#"{\#(base),"hook_event_name":"UserPromptSubmit","prompt":"fix the login bug"}"#)
        XCTAssertEqual(prompt.kind, .userPromptSubmit)
        XCTAssertEqual(prompt.summary, "", "the prompt never becomes a summary")
        let stop = try event(
            #"{\#(base),"hook_event_name":"Stop","transcript_path":"/Users/me/.copilot/session-state/c-1/events.jsonl","stop_reason":"end_turn","stop_hook_active":false}"#
        )
        XCTAssertEqual(stop.kind, .stop)
        XCTAssertEqual(stop.transcriptPath, "/Users/me/.copilot/session-state/c-1/events.jsonl")
    }

    func testPreCompact() throws {
        XCTAssertEqual(
            try event(#"{\#(base),"hook_event_name":"PreCompact","trigger":"auto","custom_instructions":""}"#).kind,
            .preCompact)
    }

    func testToolHooksUseClaudeToolNamesAndCopilotPaths() throws {
        let bash = try event(
            #"{\#(base),"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run the tests"}}"#
        )
        XCTAssertEqual(bash.kind, .preToolUse)
        XCTAssertEqual(bash.toolName, "Bash")
        XCTAssertEqual(bash.summary, "npm test")
        // Copilot's file tools take `path`, not Claude Code's `file_path`.
        let edit = try event(
            #"{\#(base),"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"path":"/Users/me/site/app.js","old_str":"a","new_str":"b"}}"#
        )
        XCTAssertEqual(edit.toolInput.filePath, "/Users/me/site/app.js")
        XCTAssertEqual(edit.summary, "/Users/me/site/app.js")
        XCTAssertEqual(
            ToolLabel.describe(tool: edit.toolName ?? "", input: edit.toolInput, hidden: false).label, "Editing app.js")
    }

    func testAFailedToolEndsLikeAFinishedOne() throws {
        let failed = try event(
            #"{\#(base),"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"false"},"error":"exit 1"}"#
        )
        XCTAssertEqual(failed.kind, .postToolUse)
    }

    func testToolHooksAreSentAsToolActivity() {
        func kind(_ name: String) -> AgentProtocol.Kind {
            AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"\#(name)"}"#.utf8), source: .copilot)
        }
        XCTAssertEqual(kind("PreToolUse"), .tool)
        XCTAssertEqual(kind("PostToolUse"), .tool)
        XCTAssertEqual(kind("PostToolUseFailure"), .tool)
        XCTAssertEqual(kind("Stop"), .hook)
        XCTAssertEqual(kind("Notification"), .hook)
    }

    private let permissionPrompt =
        #""hook_event_name":"Notification","message":"Allow bash to run npm test?","title":"Permission needed","notification_type":"permission_prompt""#
    private let postTool =
        #""hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"ok""#

    func testAPermissionPromptNeedsYouUntilTheToolRuns() throws {
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"UserPromptSubmit","prompt":"x"}"#), at: now)
        XCTAssertEqual(sessions.session("c-1")?.state, .running)
        let notice = try event("{\(base),\(permissionPrompt)}")
        XCTAssertEqual(notice.kind, .notification)
        XCTAssertEqual(notice.notificationType, "permission_prompt")
        sessions.apply(notice, at: now.addingTimeInterval(1))
        XCTAssertEqual(sessions.session("c-1")?.state, .waiting)
        sessions.apply(try event("{\(base),\(postTool)}"), at: now.addingTimeInterval(4))
        XCTAssertEqual(sessions.session("c-1")?.state, .running)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"Stop","stop_reason":"end_turn"}"#), at: now)
        XCTAssertEqual(sessions.session("c-1")?.state, .finished)
    }

    /// Claude Code sends the same notification type, but its prompts reach the notch as a
    /// PermissionRequest first, so its sessions keep their state.
    func testClaudePermissionPromptNotificationsChangeNothing() throws {
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        let json = #"{"session_id":"k-1","cwd":"/x","hook_event_name":"UserPromptSubmit","prompt":"x"}"#
        sessions.apply(try AgentEvent.decode(Data(json.utf8)), at: now)
        let notice =
            #"{"session_id":"k-1","cwd":"/x","hook_event_name":"Notification","notification_type":"permission_prompt","message":"m"}"#
        sessions.apply(try AgentEvent.decode(Data(notice.utf8)), at: now.addingTimeInterval(1))
        XCTAssertEqual(sessions.session("k-1")?.state, .running)
    }

    func testAnElicitationNeedsYou() throws {
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1_000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"UserPromptSubmit","prompt":"x"}"#), at: now)
        sessions.apply(
            try event(
                #"{\#(base),"hook_event_name":"Notification","message":"Pick one","notification_type":"elicitation_dialog"}"#
            ), at: now.addingTimeInterval(1))
        XCTAssertEqual(sessions.session("c-1")?.state, .waiting)
    }

    /// The reference shows the Notification payload with `sessionId` and a numeric timestamp.
    func testANotificationWithCamelCaseFieldsFindsItsSession() throws {
        let notice = try event(
            #"{"sessionId":"c-1","timestamp":1762509600000,"cwd":"/Users/me/site","hook_event_name":"Notification","message":"m","notification_type":"permission_prompt"}"#
        )
        XCTAssertEqual(notice.sessionID, "c-1")
        XCTAssertEqual(notice.notificationType, "permission_prompt")
    }

    /// Hooks under camelCase names get camelCase payloads; Wisp installs PascalCase ones, but
    /// reads both.
    func testCamelCaseEventsAndFields() throws {
        let camel = #""sessionId":"c-2","timestamp":1762509600000,"cwd":"/Users/me/api""#
        let prompt = try event(#"{\#(camel),"hookEventName":"userPromptSubmitted","prompt":"x"}"#)
        XCTAssertEqual(prompt.kind, .userPromptSubmit)
        XCTAssertEqual(prompt.sessionID, "c-2")
        XCTAssertEqual(prompt.project, "api")
        let tool = try event(
            #"{\#(camel),"hookEventName":"preToolUse","toolName":"bash","toolArgs":"{\"command\":\"ls -la\"}"}"#)
        XCTAssertEqual(tool.kind, .preToolUse)
        XCTAssertEqual(tool.toolName, "bash")
        XCTAssertEqual(tool.summary, "ls -la")
        let stop = try event(
            #"{\#(camel),"hookEventName":"agentStop","transcriptPath":"/t.jsonl","stopReason":"end_turn"}"#)
        XCTAssertEqual(stop.kind, .stop)
        XCTAssertEqual(stop.transcriptPath, "/t.jsonl")
        let notice = try event(#"{\#(camel),"hookEventName":"notification","notificationType":"permission_prompt"}"#)
        XCTAssertEqual(notice.kind, .notification)
        XCTAssertEqual(notice.notificationType, "permission_prompt")
    }

    func testOtherEventsAreIgnored() throws {
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#).kind, .other)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"ErrorOccurred"}"#).kind, .other)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"BeforeAgent"}"#).kind, .other)
        XCTAssertEqual(try event(#"{\#(base)}"#).kind, .other)
    }

    func testMonitorOnlyNeverReplies() {
        XCTAssertNil(adapter.reply(.decide(.tool, allow: true, input: nil)))
        XCTAssertNil(adapter.reply(.deny(.tool, reason: "no")))
        XCTAssertNil(adapter.reply(.answer(input: .object([:]), answers: [:])))
        XCTAssertEqual(adapter.prompt(tool: "ExitPlanMode"), .tool)
    }

    /// Copilot's own names, for tools with no Claude Code name or hooks under camelCase names.
    func testCopilotToolNamesGetLabels() {
        func label(_ tool: String, _ input: ToolInput) -> String {
            ToolLabel.describe(tool: tool, input: input, hidden: false).label
        }
        XCTAssertEqual(label("bash", ToolInput(command: "npm test")), "Running npm test")
        XCTAssertEqual(label("edit", ToolInput(filePath: "/a/b/app.js")), "Editing app.js")
        XCTAssertEqual(label("create", ToolInput(filePath: "/a/new.md")), "Editing new.md")
        XCTAssertEqual(label("view", ToolInput(filePath: "/a/c.swift")), "Reading c.swift")
        XCTAssertEqual(label("grep", ToolInput(pattern: "TODO")), "Searching TODO")
        XCTAssertEqual(label("glob", ToolInput(pattern: "*.ts")), "Searching *.ts")
    }
}

final class CopilotHookFileTests: XCTestCase {
    private let file = AgentSource.copilot.adapter.hookFile
    private let helper = "/A/wisp-agent"
    private var command: String { HookInstaller.command(helper: helper, file: file) }

    private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    /// A missing helper (Wisp moved or deleted) must not make Copilot deny every tool call.
    func testTheCommandFailsOpen() {
        XCTAssertEqual(command, "'/A/wisp-agent' --source copilot || true")
        XCTAssertEqual(HookInstaller.command(helper: helper, file: file, timeout: 600), command)
        XCTAssertEqual(
            HookInstaller.command(helper: helper, file: AgentSource.codex.adapter.hookFile),
            "'/A/wisp-agent' --source codex")
    }

    /// GitHub documents `~/.copilot/hooks/*.json` as handlers listed directly under each event.
    func testWritesAVersionedFileOfFlatHandlers() throws {
        let out = try json(HookInstaller.install(into: Data(), command: command, file: file, tools: true))
        XCTAssertEqual(out["version"], .number(1))
        let handler = out["hooks"]?["PreToolUse"]?[0]
        XCTAssertEqual(handler?["type"], .string("command"))
        XCTAssertEqual(handler?["command"], .string(command))
        XCTAssertEqual(handler?["timeoutSec"], .number(5))
        XCTAssertNil(handler?["timeout"])
        XCTAssertNil(handler?["async"])
        XCTAssertNil(handler?["hooks"], "no Claude-style groups")
        XCTAssertNil(handler?["matcher"], "no matcher matches every call")
        XCTAssertEqual(out["hooks"]?["Notification"]?.count, 1)
        XCTAssertNil(out["hooks"]?["Notification"]?[0]?["matcher"])
        XCTAssertNil(out["hooks"]?["PermissionRequest"])
        XCTAssertEqual(out["hooks"]?["PostToolUseFailure"]?[0]?["command"], .string(command))
    }

    func testAToolArgumentsStringIsReadUnderPascalCaseToo() throws {
        let event = try XCTUnwrap(
            AgentSource.copilot.adapter.parse(
                JSONDecoder().decode(
                    JSONValue.self,
                    from: Data(
                        #"{"session_id":"c-1","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":"{\"command\":\"make\"}"}"#
                            .utf8)), terminal: nil))
        XCTAssertEqual(event.summary, "make")
    }

    func testRemovingLeavesNothingOfWispsOwnFile() throws {
        let installed = try HookInstaller.install(into: Data(), command: command, file: file, tools: true)
        let removed = try HookInstaller.remove(from: installed)
        XCTAssertTrue(try HookInstaller.isLeftEmpty(removed, file: file))
        XCTAssertFalse(try HookInstaller.isInstalled(in: removed))
        let shared = try HookInstaller.install(
            into: Data(#"{"version":1,"hooks":{"Stop":[{"type":"command","command":"./mine.sh"}]}}"#.utf8),
            command: command, file: file)
        XCTAssertFalse(try HookInstaller.isLeftEmpty(HookInstaller.remove(from: shared), file: file))
        // Never for a file the agent shares with the user's settings.
        let claude = AgentSource.claude.adapter.hookFile
        XCTAssertFalse(try HookInstaller.isLeftEmpty(Data("{}".utf8), file: claude))
    }

    func testOtherAgentsKeepTheirMatchersAndNoVersion() throws {
        let out = try json(
            HookInstaller.install(into: Data("{}".utf8), command: "'/A/wisp-agent'", source: .claude))
        XCTAssertNil(out["version"])
        XCTAssertEqual(out["hooks"]?["Stop"]?[0]?["matcher"], .string(""))
    }

    func testLinkAndToolActivity() throws {
        let data = try HookInstaller.install(into: Data(), command: command, file: file)
        XCTAssertNil(try json(data)["hooks"]?["PreToolUse"])
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: data, file: file))
        XCTAssertEqual(try HookInstaller.link(in: data, helper: helper, file: file), .this)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: helper, file: file, timeout: 600), .this)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/B/wisp-agent", file: file), .other)
        let withTools = try HookInstaller.install(into: data, command: command, file: file, tools: true)
        XCTAssertTrue(try HookInstaller.toolsInstalled(in: withTools, file: file))
        XCTAssertEqual(try HookInstaller.link(in: withTools, helper: helper, file: file), .this)
        XCTAssertEqual(try json(withTools)["hooks"]?["Stop"]?.count, 1, "reinstalling doesn't duplicate")
        XCTAssertNil(try HookInstaller.installedApprovalTimeout(in: withTools))
    }

    func testKeepsTheUsersOwnHooks() throws {
        let settings = Data(
            #"{"version":1,"hooks":{"preToolUse":[{"type":"command","bash":"./check.sh","timeoutSec":10}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./lint.sh"}]}]}}"#
                .utf8)
        let installed = try HookInstaller.install(into: settings, command: command, file: file, tools: true)
        let out = try json(installed)
        XCTAssertEqual(out["hooks"]?["preToolUse"]?[0]?["bash"], .string("./check.sh"))
        XCTAssertEqual(out["hooks"]?["PreToolUse"]?[0]?["matcher"], .string("Bash"))
        XCTAssertEqual(out["hooks"]?["PreToolUse"]?[1]?["command"], .string(command))
        let removed = try json(HookInstaller.remove(from: installed))
        XCTAssertEqual(removed["version"], .number(1))
        XCTAssertEqual(removed["hooks"]?["preToolUse"]?[0]?["bash"], .string("./check.sh"))
        XCTAssertEqual(removed["hooks"]?["PreToolUse"]?[0]?["hooks"]?[0]?["command"], .string("./lint.sh"))
        XCTAssertNil(removed["hooks"]?["PreToolUse"]?[1])
        XCTAssertNil(removed["hooks"]?["SessionStart"])
    }

    /// A flat handler of the user's own that isn't Wisp's stays when Wisp's go.
    func testFlatHandlersAreRecognisedByTheHelperName() throws {
        let installed = try HookInstaller.install(
            into: Data(#"{"version":1,"hooks":{"Stop":[{"type":"command","command":"./mine.sh"}]}}"#.utf8),
            command: command, file: file)
        XCTAssertEqual(try json(installed)["hooks"]?["Stop"]?.count, 2)
        XCTAssertEqual(try HookInstaller.link(in: installed, helper: helper, file: file), .this)
        let removed = try json(HookInstaller.remove(from: installed))
        XCTAssertEqual(removed["hooks"]?["Stop"]?.count, 1)
        XCTAssertEqual(removed["hooks"]?["Stop"]?[0]?["command"], .string("./mine.sh"))
    }

    /// The hook file lives in a temporary home; nothing touches the real ~/.copilot.
    func testInstallsUnderAGivenHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let url = file.url(home: home)
        XCTAssertEqual(url.path, home.path + "/.copilot/hooks/wisp.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HookInstaller.install(into: Data(), command: command, file: file).write(to: url)
        XCTAssertEqual(try HookInstaller.link(in: Data(contentsOf: url), helper: helper, file: file), .this)
    }
}
