import XCTest

@testable import WispCore

final class AgentEventTests: XCTestCase {
    private func decode(_ json: String) throws -> AgentEvent {
        try AgentEvent.decode(Data(json.utf8))
    }

    func testDecodesPermissionRequestWithBashSummary() throws {
        let event = try decode(
            """
            {"session_id":"s1","cwd":"/Users/me/code/wisp","hook_event_name":"PermissionRequest",
             "tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Clean"},"transcript_path":"/x"}
            """)
        XCTAssertEqual(event.kind, .permissionRequest)
        XCTAssertEqual(event.sessionID, "s1")
        XCTAssertEqual(event.project, "wisp")
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.summary, "rm -rf build")
    }

    func testSummaryFallsBackToFilePathThenDescription() throws {
        let edit = try decode(
            #"{"session_id":"s","cwd":"/a","hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"/a/b.swift","old_string":"x"}}"#
        )
        XCTAssertEqual(edit.summary, "/a/b.swift")
        let other = try decode(
            #"{"session_id":"s","cwd":"/a","hook_event_name":"PermissionRequest","tool_name":"X","tool_input":{"n":3}}"#
        )
        XCTAssertEqual(other.summary, "")
    }

    func testDecodesNotificationAndUnknownEvents() throws {
        let note = try decode(
            #"{"session_id":"s","cwd":"/a","hook_event_name":"Notification","message":"Claude needs your permission","notification_type":"permission_prompt"}"#
        )
        XCTAssertEqual(note.kind, .notification)
        XCTAssertEqual(note.message, "Claude needs your permission")
        let resume = try decode(#"{"session_id":"s","hook_event_name":"SessionStart","source":"resume"}"#)
        XCTAssertTrue(resume.isResume)
        XCTAssertFalse(try decode(#"{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}"#).isResume)
        let unknown = try decode(#"{"session_id":"s","hook_event_name":"SubagentStart"}"#)
        XCTAssertEqual(unknown.kind, .other)
        XCTAssertEqual(unknown.project, "Claude")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try decode("not json"))
    }
}

final class AgentSessionsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    private func event(_ kind: String, session: String = "s1", extra: String = "") throws -> AgentEvent {
        try AgentEvent.decode(
            Data(#"{"session_id":"\#(session)","cwd":"/p/app","hook_event_name":"\#(kind)"\#(extra)}"#.utf8))
    }

    func testLifecycle() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("SessionStart"), at: start)
        XCTAssertEqual(sessions.list.first?.state, .idle)
        sessions.apply(try event("UserPromptSubmit"), at: start.addingTimeInterval(1))
        XCTAssertEqual(sessions.list.first?.state, .running)
        XCTAssertEqual(sessions.list.first?.turnStarted, start.addingTimeInterval(1))
        sessions.apply(try event("PermissionRequest", extra: #","tool_name":"Bash""#), at: start.addingTimeInterval(2))
        XCTAssertEqual(sessions.list.first?.state, .needsApproval)
        sessions.resolveApproval(session: "s1", at: start.addingTimeInterval(3))
        XCTAssertEqual(sessions.list.first?.state, .running)
        sessions.apply(try event("Stop"), at: start.addingTimeInterval(4))
        XCTAssertEqual(sessions.list.first?.state, .finished)
        sessions.apply(try event("SessionEnd"), at: start.addingTimeInterval(5))
        XCTAssertTrue(sessions.list.isEmpty)
    }

    func testIdleNotificationMeansWaiting() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("Notification", extra: #","notification_type":"idle_prompt""#), at: start)
        XCTAssertEqual(sessions.list.first?.state, .waiting)
        XCTAssertTrue(sessions.anyNeedsUser)
    }

    func testUnknownSessionIsCreatedOnFirstEventAndListIsNewestFirst() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit", session: "a"), at: start)
        sessions.apply(try event("UserPromptSubmit", session: "b"), at: start.addingTimeInterval(1))
        XCTAssertEqual(sessions.list.map(\.id), ["b", "a"])
    }

    func testStaleSessionsArePruned() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("Stop", session: "old"), at: start)
        sessions.apply(try event("UserPromptSubmit", session: "new"), at: start.addingTimeInterval(7200))
        sessions.prune(now: start.addingTimeInterval(7200), olderThan: 3600)
        XCTAssertEqual(sessions.list.map(\.id), ["new"])
    }
}

final class PermissionReplyTests: XCTestCase {
    func testAllowAndDenyJSON() throws {
        let allow = try XCTUnwrap(PermissionReply.json(allow: true))
        let object = try JSONDecoder().decode(JSONValue.self, from: Data(allow.utf8))
        XCTAssertEqual(object["hookSpecificOutput"]?["hookEventName"], .string("PermissionRequest"))
        XCTAssertEqual(object["hookSpecificOutput"]?["decision"]?["behavior"], .string("allow"))
        let deny = try XCTUnwrap(PermissionReply.json(allow: false))
        let denied = try JSONDecoder().decode(JSONValue.self, from: Data(deny.utf8))
        XCTAssertEqual(denied["hookSpecificOutput"]?["decision"]?["behavior"], .string("deny"))
        XCTAssertNotNil(denied["hookSpecificOutput"]?["decision"]?["message"])
    }

    /// Claude Code ignores a bare allow for a plan; it needs the input echoed back.
    func testAllowCarriesTheInputBack() throws {
        let input: JSONValue = .object(["plan": .string("# Fix"), "planFilePath": .string("/p/plan.md")])
        let allow = try XCTUnwrap(PermissionReply.json(allow: true, updatedInput: input))
        let object = try JSONDecoder().decode(JSONValue.self, from: Data(allow.utf8))
        XCTAssertEqual(object["hookSpecificOutput"]?["decision"]?["updatedInput"], input)
        let deny = try XCTUnwrap(PermissionReply.json(allow: false, updatedInput: input))
        let denied = try JSONDecoder().decode(JSONValue.self, from: Data(deny.utf8))
        XCTAssertNil(denied["hookSpecificOutput"]?["decision"]?["updatedInput"])
        let plain = try XCTUnwrap(PermissionReply.json(allow: true))
        let plainObject = try JSONDecoder().decode(JSONValue.self, from: Data(plain.utf8))
        XCTAssertNil(plainObject["hookSpecificOutput"]?["decision"]?["updatedInput"])
    }
}

final class PermissionPromptTests: XCTestCase {
    private func request(_ tool: String, input: String) throws -> AgentEvent {
        try AgentEvent.decode(
            Data(
                #"{"session_id":"s","cwd":"/p/app","hook_event_name":"PermissionRequest","tool_name":"\#(tool)","tool_input":\#(input)}"#
                    .utf8))
    }

    func testKinds() {
        XCTAssertEqual(PermissionPrompt(tool: "ExitPlanMode"), .plan)
        XCTAssertEqual(PermissionPrompt(tool: "AskUserQuestion"), .question)
        XCTAssertEqual(PermissionPrompt(tool: "Bash"), .tool)
        XCTAssertEqual(PermissionPrompt(tool: nil), .tool)
    }

    func testAPlanKeepsItsInputAndIsSummedUpByItsTitle() throws {
        let event = try request(
            "ExitPlanMode", input: #"{"plan":"\n# Two agent fixes\n\nBody","planFilePath":"/p/plan.md"}"#)
        XCTAssertEqual(event.prompt, .plan)
        XCTAssertEqual(event.rawToolInput?["planFilePath"], .string("/p/plan.md"))
        XCTAssertEqual(event.summary, "Two agent fixes")
    }

    func testAToolRequestKeepsItsInputToo() throws {
        let event = try request("Bash", input: #"{"command":"ls"}"#)
        XCTAssertEqual(event.prompt, .tool)
        XCTAssertEqual(event.rawToolInput?["command"], .string("ls"))
        XCTAssertEqual(event.summary, "ls")
    }

    /// Only the terminal can pick an answer, so a question shows as Needs you, not a card.
    func testAQuestionWaitsForTheUser() throws {
        var sessions = AgentSessions()
        sessions.apply(try request("AskUserQuestion", input: #"{"questions":[]}"#), at: Date())
        XCTAssertEqual(sessions.list.first?.state, .waiting)
    }

    /// Allow All covers tools, never a plan or a question.
    func testAllowAllSkipsPlansAndQuestions() throws {
        var sessions = AgentSessions()
        sessions.apply(try request("Bash", input: #"{"command":"ls"}"#), at: Date())
        sessions.allowAll(session: "s")
        XCTAssertTrue(sessions.shouldAutoApprove(try request("Bash", input: "{}")))
        XCTAssertFalse(sessions.shouldAutoApprove(try request("ExitPlanMode", input: "{}")))
        XCTAssertFalse(sessions.shouldAutoApprove(try request("AskUserQuestion", input: "{}")))
    }
}

final class HookInstallerTests: XCTestCase {
    private let command = "'/Apps/Wisp.app/Contents/Helpers/wisp-agent'"

    private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    func testInstallIntoEmptySettings() throws {
        let out = try json(HookInstaller.install(into: Data("{}".utf8), command: command))
        for event in HookInstaller.events {
            XCTAssertNotNil(out["hooks"]?[event], event)
        }
        XCTAssertEqual(out["hooks"]?["PermissionRequest"]?[0]?["hooks"]?[0]?["timeout"], .number(120))
    }

    func testInstallKeepsOtherSettingsAndHooks() throws {
        let existing = """
            {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
            """
        let out = try json(HookInstaller.install(into: Data(existing.utf8), command: command))
        XCTAssertEqual(out["model"], .string("opus"))
        XCTAssertEqual(out["hooks"]?["Stop"]?.count, 2)
        XCTAssertEqual(out["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["command"], .string("say done"))
    }

    func testInstallTwiceDoesNotDuplicate() throws {
        let once = try HookInstaller.install(into: Data("{}".utf8), command: command)
        let twice = try json(HookInstaller.install(into: once, command: command))
        XCTAssertEqual(twice["hooks"]?["Stop"]?.count, 1)
    }

    func testRemoveLeavesOnlyTheUsersHooks() throws {
        let existing = """
            {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
            """
        let installed = try HookInstaller.install(into: Data(existing.utf8), command: command)
        let removed = try json(HookInstaller.remove(from: installed))
        XCTAssertEqual(removed, try json(Data(existing.utf8)))
    }

    func testRemoveDropsAnEmptyHooksObject() throws {
        let installed = try HookInstaller.install(into: Data("{}".utf8), command: command)
        XCTAssertEqual(try json(HookInstaller.remove(from: installed)), .object([:]))
    }

    func testIsInstalled() throws {
        XCTAssertFalse(try HookInstaller.isInstalled(in: Data("{}".utf8)))
        XCTAssertTrue(try HookInstaller.isInstalled(in: HookInstaller.install(into: Data("{}".utf8), command: command)))
    }

    func testEmptyUserEntriesDoNotCountAsInstalled() throws {
        let existing = Data(#"{"hooks":{"PreToolUse":[],"Stop":[{"matcher":"","hooks":[]}]}}"#.utf8)
        XCTAssertFalse(try HookInstaller.isInstalled(in: existing))
        XCTAssertEqual(try json(HookInstaller.remove(from: existing)), try json(existing))
    }

    func testCommandQuotesTheHelperAndTagsCodex() {
        XCTAssertEqual(HookInstaller.command(helper: "/A/wisp-agent", source: .claude), "'/A/wisp-agent'")
        XCTAssertEqual(
            HookInstaller.command(helper: "/A/wisp-agent", source: .codex), "'/A/wisp-agent' --source codex")
        XCTAssertEqual(HookInstaller.command(helper: "/It's/wisp-agent", source: .claude), #"'/It'\''s/wisp-agent'"#)
    }

    func testLinkSeesNoHooks() throws {
        XCTAssertEqual(try HookInstaller.link(in: Data("{}".utf8), helper: installedHelper, source: .claude), .none)
    }

    func testLinkSeesThisCopy() throws {
        for source in [AgentSource.claude, .codex] {
            let settings = try installed(helper: installedHelper, source: source)
            XCTAssertEqual(try HookInstaller.link(in: settings, helper: installedHelper, source: source), .this)
        }
    }

    func testLinkSeesAnotherCopy() throws {
        let settings = try installed(helper: devHelper, source: .claude)
        XCTAssertEqual(try HookInstaller.link(in: settings, helper: installedHelper, source: .claude), .other)
        XCTAssertEqual(try HookInstaller.link(in: settings, helper: devHelper, source: .claude), .this)
    }

    func testLinkHandlesAQuoteInThePath() throws {
        let helper = "/Users/o'neil/Wisp.app/Contents/MacOS/wisp-agent"
        let settings = try installed(helper: helper, source: .claude)
        XCTAssertEqual(try HookInstaller.link(in: settings, helper: helper, source: .claude), .this)
    }

    func testAMixOfCopiesIsAnotherCopy() throws {
        let this = HookInstaller.command(helper: installedHelper, source: .claude)
        let other = HookInstaller.command(helper: devHelper, source: .claude)
        let settings: JSONValue = .object([
            "hooks": .object([
                "Stop": .array(
                    [this, other].map { command in
                        .object([
                            "matcher": .string(""),
                            "hooks": .array([.object(["type": .string("command"), "command": .string(command)])]),
                        ])
                    })
            ])
        ])
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: installedHelper, source: .claude), .other)
    }

    private let installedHelper = "/Applications/Wisp.app/Contents/MacOS/wisp-agent"
    private let devHelper = "/Users/me/wisp/build/Build/Products/Debug/Wisp.app/Contents/MacOS/wisp-agent"

    private func installed(helper: String, source: AgentSource) throws -> Data {
        try HookInstaller.install(
            into: Data("{}".utf8), command: HookInstaller.command(helper: helper, source: source), source: source)
    }

    func testRemoveKeepsTheUsersEmptyEntries() throws {
        let existing = Data(#"{"hooks":{"PreToolUse":[]}}"#.utf8)
        let installed = try HookInstaller.install(into: existing, command: command)
        XCTAssertEqual(try json(HookInstaller.remove(from: installed)), try json(existing))
    }

    func testRejectsNonObjectSettings() {
        XCTAssertThrowsError(try HookInstaller.install(into: Data("[]".utf8), command: command))
    }
}
