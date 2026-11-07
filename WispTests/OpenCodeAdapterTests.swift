import XCTest

@testable import WispCore

/// What Wisp's OpenCode plugin hands the helper, built from the event shapes in OpenCode
/// v1.19.5's source (`packages/schema/src/v1`, `session-status-event.ts`, the plugin `Hooks`
/// type in `@opencode-ai/plugin` 1.19.5), checked on 2026-11-07. OpenCode wasn't installed, so
/// the values are made up; `OpenCodePluginScriptTests` runs the plugin itself on those events.
final class OpenCodeAdapterTests: XCTestCase {
    private let adapter = AgentSource.opencode.adapter

    private func event(_ text: String) throws -> AgentEvent {
        try XCTUnwrap(adapter.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), terminal: nil))
    }

    private let base = #""session_id":"ses_1","cwd":"/Users/me/site""#

    func testNameFileAndCapabilities() {
        XCTAssertEqual(adapter.displayName, "OpenCode")
        XCTAssertEqual(adapter.fallbackProject, "OpenCode")
        XCTAssertEqual(adapter.hookFile.displayPath, "~/.config/opencode/plugins/wisp.js")
        XCTAssertEqual(adapter.hookFile.format, .opencodePlugin)
        XCTAssertTrue(adapter.hookFile.format.isPlugin)
        XCTAssertFalse(AgentSource.gemini.adapter.hookFile.format.isPlugin)
        XCTAssertEqual(adapter.hookFile.helperArguments, " --source opencode")
        XCTAssertFalse(adapter.hookFile.statusLine)
        XCTAssertTrue(adapter.hookFile.waitsForApproval, "the plugin holds a permission request for the notch")
        XCTAssertTrue(adapter.capabilities.contains(.approve))
        XCTAssertTrue(adapter.capabilities.contains(.toolActivity))
        XCTAssertTrue(adapter.capabilities.contains(.compaction))
        XCTAssertFalse(adapter.capabilities.contains(.answerQuestions))
        XCTAssertFalse(adapter.capabilities.contains(.rules))
        XCTAssertFalse(adapter.capabilities.contains(.statusLine))
        XCTAssertFalse(adapter.capabilities.contains(.limits))
    }

    func testRegisteredWithItsWireID() {
        XCTAssertEqual(AgentSource(rawValue: "opencode"), .opencode)
        XCTAssertEqual(AgentAdapters.adapter(id: "opencode")?.displayName, "OpenCode")
    }

    func testSessionLifecycle() throws {
        let start = try event(#"{\#(base),"hook_event_name":"session.created"}"#)
        XCTAssertEqual(start.kind, .sessionStart)
        XCTAssertEqual(start.source, .opencode)
        XCTAssertEqual(start.sessionID, "ses_1")
        XCTAssertEqual(start.project, "site")
        XCTAssertEqual(
            try event(#"{\#(base),"hook_event_name":"session.status","status":"busy"}"#).kind, .userPromptSubmit)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"session.status","status":"idle"}"#).kind, .stop)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"session.status","status":"retry"}"#).kind, .other)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"session.deleted"}"#).kind, .sessionEnd)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"session.compacting"}"#).kind, .preCompact)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"session.compacted"}"#).kind, .postCompact)
    }

    func testClaudeNamesAndUnknownEventsAreOther() throws {
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"SessionStart"}"#).kind, .other)
        XCTAssertEqual(try event(#"{\#(base),"hook_event_name":"message.updated"}"#).kind, .other)
        XCTAssertEqual(try event(#"{"cwd":"/"}"#).kind, .other)
        XCTAssertEqual(try event(#"{"cwd":"/"}"#).project, "OpenCode")
    }

    func testShellPermissionIsAToolRequest() throws {
        let request = try event(
            #"{\#(base),"hook_event_name":"permission.asked","request_id":"per_1","permission":"bash","patterns":["npm test"],"metadata":{"command":"npm test"}}"#
        )
        XCTAssertEqual(request.kind, .permissionRequest)
        XCTAssertEqual(request.toolName, "bash")
        XCTAssertEqual(request.toolUseID, "per_1")
        XCTAssertEqual(request.summary, "npm test")
        XCTAssertEqual(request.toolInput.command, "npm test")
        XCTAssertEqual(request.prompt, .tool)
        XCTAssertEqual(
            AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"permission.asked"}"#.utf8), source: .opencode), .hook
        )
    }

    func testEditReadFetchAndFolderPermissions() throws {
        let edit = try event(
            #"{\#(base),"hook_event_name":"permission.asked","request_id":"per_2","permission":"edit","patterns":["src/app.ts"],"metadata":{"filepath":"/Users/me/site/src/app.ts"}}"#
        )
        XCTAssertEqual(edit.toolInput.filePath, "/Users/me/site/src/app.ts")
        XCTAssertEqual(edit.summary, "/Users/me/site/src/app.ts")
        let read = try event(
            #"{\#(base),"hook_event_name":"permission.asked","request_id":"per_3","permission":"read","patterns":["secrets/.env"],"metadata":{}}"#
        )
        XCTAssertEqual(read.toolInput.filePath, "secrets/.env", "read sends only the pattern")
        let fetch = try event(
            #"{\#(base),"hook_event_name":"permission.asked","request_id":"per_4","permission":"webfetch","patterns":["https://example.com/a"],"metadata":{"url":"https://example.com/a"}}"#
        )
        XCTAssertEqual(fetch.toolInput.url, "https://example.com/a")
        let folder = try event(
            #"{\#(base),"hook_event_name":"permission.asked","request_id":"per_5","permission":"external_directory","patterns":["/tmp/*"],"metadata":{"filepath":"/tmp/x.log"}}"#
        )
        XCTAssertEqual(folder.toolInput.filePath, "/tmp/x.log")
        let task = try event(
            #"{\#(base),"hook_event_name":"permission.asked","request_id":"per_6","permission":"task","patterns":["explore"],"metadata":{"description":"Find the router","subagent_type":"explore"}}"#
        )
        XCTAssertEqual(task.summary, "Find the router")
        XCTAssertEqual(task.toolInput.subagentType, "explore")
        let other = try event(
            #"{\#(base),"hook_event_name":"permission.asked","request_id":"per_7","permission":"doom_loop","patterns":["*"],"metadata":{}}"#
        )
        XCTAssertEqual(other.summary, "", "a wildcard pattern isn't worth showing")
    }

    func testAnsweredRequestsAndQuestionsAreToolActivityThatClearsNeedsYou() throws {
        for name in ["permission.replied", "question.replied", "question.rejected"] {
            let payload = #"{\#(base),"hook_event_name":"\#(name)","request_id":"que_1"}"#
            let answered = try event(payload)
            XCTAssertEqual(answered.kind, .postToolUse, name)
            XCTAssertEqual(answered.toolUseID, "que_1", "never matches a running tool, so none is ended")
            XCTAssertEqual(AgentProtocol.kind(forHook: Data(payload.utf8), source: .opencode), .tool, name)
        }
    }

    func testQuestionIsNeedsYou() throws {
        let asked = try event(#"{\#(base),"hook_event_name":"question.asked","request_id":"que_1"}"#)
        XCTAssertEqual(asked.kind, .notification)
        XCTAssertEqual(asked.notificationType, OpenCodeHooks.question)
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"session.status","status":"busy"}"#), at: now)
        sessions.apply(asked, at: now)
        XCTAssertEqual(sessions.session("ses_1")?.state, .waiting)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"question.replied","request_id":"que_1"}"#), at: now)
        XCTAssertEqual(sessions.session("ses_1")?.state, .running)
    }

    func testAnAnswerOpenCodeDidntTakeIsNeedsYou() throws {
        let failed = try event(#"{\#(base),"hook_event_name":"permission.reply_failed","request_id":"per_1"}"#)
        XCTAssertEqual(failed.kind, .notification)
        XCTAssertEqual(failed.notificationType, OpenCodeHooks.replyFailed)
        var sessions = AgentSessions()
        let now = Date(timeIntervalSince1970: 1000)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"session.status","status":"busy"}"#), at: now)
        sessions.apply(failed, at: now)
        XCTAssertEqual(sessions.session("ses_1")?.state, .waiting)
        sessions.apply(try event(#"{\#(base),"hook_event_name":"permission.replied","request_id":"per_1"}"#), at: now)
        XCTAssertEqual(sessions.session("ses_1")?.state, .running, "answered at OpenCode's own prompt")
    }

    func testToolHooksMapToToolActivity() throws {
        let before = try event(
            #"{\#(base),"hook_event_name":"tool.execute.before","tool":"edit","call_id":"call_1","args":{"filePath":"/Users/me/site/a.ts"}}"#
        )
        XCTAssertEqual(before.kind, .preToolUse)
        XCTAssertEqual(before.toolName, "edit")
        XCTAssertEqual(before.toolUseID, "call_1")
        XCTAssertEqual(before.toolInput.filePath, "/Users/me/site/a.ts")
        XCTAssertEqual(ToolLabel.describe(tool: "edit", input: before.toolInput, hidden: false).label, "Editing a.ts")
        let after = try event(
            #"{\#(base),"hook_event_name":"tool.execute.after","tool":"bash","call_id":"call_2","args":{"command":"ls"}}"#
        )
        XCTAssertEqual(after.kind, .postToolUse)
        XCTAssertEqual(after.toolUseID, "call_2")
        XCTAssertEqual(after.summary, "ls")
    }

    func testOpenCodeToolNamesGetLabels() {
        func label(_ tool: String, _ input: ToolInput) -> String {
            ToolLabel.describe(tool: tool, input: input, hidden: false).label
        }
        XCTAssertEqual(label("bash", ToolInput(command: "npm test")), "Running npm test")
        XCTAssertEqual(label("write", ToolInput(filePath: "/a/b.md")), "Editing b.md")
        XCTAssertEqual(label("read", ToolInput(filePath: "/a/c.swift")), "Reading c.swift")
        XCTAssertEqual(label("grep", ToolInput(pattern: "TODO")), "Searching TODO")
        XCTAssertEqual(label("webfetch", ToolInput(url: "https://example.com/x")), "Fetching example.com")
        XCTAssertEqual(label("websearch", ToolInput()), "Searching the web")
    }

    func testReplies() {
        XCTAssertEqual(adapter.reply(.allow(.tool, input: nil)), #"{"reply":"once"}"#)
        XCTAssertEqual(adapter.reply(.deny(.tool, reason: "")), #"{"reply":"reject"}"#, "a plain reject, as in the TUI")
        XCTAssertEqual(
            adapter.reply(.deny(.tool, reason: " use pnpm ")),
            #"{"message":"Denied from the Wisp notch: use pnpm","reply":"reject"}"#)
        XCTAssertNil(adapter.reply(.answer(input: .object([:]), answers: [:])))
    }

    // MARK: Plugin file

    private let helper = "/Applications/Wisp.app/Contents/MacOS/wisp-agent"
    private var file: HookFile { adapter.hookFile }

    private func plugin(timeout: Int = HookInstaller.approvalTimeout, tools: Bool = false, helper: String? = nil)
        throws -> Data
    {
        let command = HookInstaller.command(helper: helper ?? self.helper, file: file, timeout: timeout)
        return try HookInstaller.install(into: Data(), command: command, file: file, tools: tools, timeout: timeout)
    }

    func testPluginEmbedsTheCommandAndToolSwitch() throws {
        let text = String(decoding: try plugin(timeout: 600, tools: true), as: UTF8.self)
        XCTAssertTrue(
            text.contains(
                #"const COMMAND = "'/Applications/Wisp.app/Contents/MacOS/wisp-agent' --source opencode --timeout 600""#
            ),
            text)
        XCTAssertTrue(text.contains("const TOOLS = true"))
        XCTAssertTrue(text.contains("export const WispPlugin"))
        XCTAssertFalse(text.contains("\u{2014}"), "no em dashes")
        XCTAssertTrue(String(decoding: try plugin(), as: UTF8.self).contains("const TOOLS = false"))
    }

    func testPluginIgnoresWhatWasThere() throws {
        let command = HookInstaller.command(helper: helper, file: file)
        let written = try HookInstaller.install(into: Data("garbage".utf8), command: command, file: file)
        XCTAssertEqual(written, try plugin())
    }

    func testPluginLink() throws {
        XCTAssertEqual(try HookInstaller.link(in: Data(), helper: helper, file: file), HookLink.none)
        XCTAssertEqual(try HookInstaller.link(in: try plugin(), helper: helper, file: file), .this)
        XCTAssertEqual(try HookInstaller.link(in: try plugin(tools: true), helper: helper, file: file), .this)
        XCTAssertEqual(
            try HookInstaller.link(
                in: try plugin(helper: "/Applications/Wisp Dev.app/x/wisp-agent"), helper: helper, file: file),
            .other)
        XCTAssertEqual(
            try HookInstaller.link(in: try plugin(timeout: 600), helper: helper, file: file, timeout: 120), .outdated,
            "push changed the wait since")
        XCTAssertEqual(
            try HookInstaller.link(in: try plugin(timeout: 600), helper: helper, file: file, timeout: 600), .this)
        // An older plugin from this copy (any other text around the same command) reads as outdated.
        var old = String(decoding: try plugin(), as: UTF8.self)
        old = old.replacingOccurrences(of: "export const WispPlugin", with: "export const OldWispPlugin")
        XCTAssertEqual(try HookInstaller.link(in: Data(old.utf8), helper: helper, file: file), .outdated)
        XCTAssertEqual(
            try HookInstaller.link(in: Data("export default {}".utf8), helper: helper, file: file), .other,
            "someone else's wisp.js")
    }

    func testPluginToolsAndTimeout() throws {
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: try plugin(), file: file))
        XCTAssertTrue(try HookInstaller.toolsInstalled(in: try plugin(tools: true), file: file))
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: Data(), file: file))
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: try plugin(), file: file), 120)
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: try plugin(timeout: 900), file: file), 900)
        XCTAssertNil(try HookInstaller.installedApprovalTimeout(in: Data(), file: file))
        // JSON hook files still read their PermissionRequest timeout.
        let claude = AgentSource.claude.adapter.hookFile
        let command = HookInstaller.command(helper: helper, file: claude, timeout: 600)
        let settings = try HookInstaller.install(into: Data(), command: command, file: claude, timeout: 600)
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: settings, file: claude), 600)
    }

    func testHelperPathWithQuotesSurvivesJavaScript() throws {
        let odd = #"/Users/o'neil/Apps/Wisp "beta".app/wisp-agent"#
        let text = String(decoding: try plugin(helper: odd), as: UTF8.self)
        XCTAssertEqual(try HookInstaller.link(in: Data(text.utf8), helper: odd, file: file), .this)
        XCTAssertEqual(OpenCodePlugin.command(in: Data(text.utf8)), HookInstaller.command(helper: odd, file: file))
    }
}
