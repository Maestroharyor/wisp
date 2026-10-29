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
        let unknown = try decode(#"{"session_id":"s","hook_event_name":"PreCompact"}"#)
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

    func testRejectsNonObjectSettings() {
        XCTAssertThrowsError(try HookInstaller.install(into: Data("[]".utf8), command: command))
    }
}
