import XCTest

@testable import WispCore

final class SessionSwitcherTests: XCTestCase {
    private let ids = ["a", "b", "c"]

    func testStartsOnTheFirstSession() {
        XCTAssertEqual(SessionSwitcher().selected(in: ids), "a")
        XCTAssertNil(SessionSwitcher().selected(in: []))
    }

    func testMovesAndWraps() {
        var switcher = SessionSwitcher()
        switcher.move(1, in: ids)
        XCTAssertEqual(switcher.selected(in: ids), "b")
        switcher.move(1, in: ids)
        switcher.move(1, in: ids)
        XCTAssertEqual(switcher.selected(in: ids), "a", "Down past the last goes to the first")
        switcher.move(-1, in: ids)
        XCTAssertEqual(switcher.selected(in: ids), "c", "Up past the first goes to the last")
    }

    func testTheSelectionFollowsItsSessionWhenTheListReorders() {
        var switcher = SessionSwitcher()
        switcher.move(1, in: ids)
        XCTAssertEqual(switcher.selected(in: ["b", "c", "a"]), "b")
    }

    func testASessionThatEndedFallsBackToTheFirst() {
        var switcher = SessionSwitcher()
        switcher.select("b")
        XCTAssertEqual(switcher.selected(in: ["a", "c"]), "a")
        switcher.reset()
        XCTAssertEqual(switcher.selected(in: ids), "a")
    }

    func testMovingAnEmptyListDoesNothing() {
        var switcher = SessionSwitcher()
        switcher.move(1, in: [])
        XCTAssertNil(switcher.selected(in: []))
    }

    func testKeys() {
        XCTAssertEqual(SessionSwitcher.key(126), .up)
        XCTAssertEqual(SessionSwitcher.key(125), .down)
        XCTAssertEqual(SessionSwitcher.key(36), .jump)
        XCTAssertEqual(SessionSwitcher.key(76), .jump)
        XCTAssertNil(SessionSwitcher.key(KeyCodes.escape))
    }

    func testStatusLines() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = AgentSession(id: "s", project: "api", state: .needsApproval, turnStarted: now, updated: now)
        XCTAssertEqual(SessionSwitcher.status(session), "Needs approval")
        session.state = .running
        XCTAssertEqual(SessionSwitcher.status(session), "Working")
        session.compacting = true
        XCTAssertEqual(SessionSwitcher.status(session), "Compacting")
    }

    func testARequestHeldByTheSpendCapSaysSo() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var sessions = AgentSessions()
        let ask = try XCTUnwrap(
            AgentSource.claude.adapter.parse(
                .object([
                    "session_id": .string("s"), "hook_event_name": .string("PermissionRequest"),
                    "tool_name": .string("Bash"), "cwd": .string("/p"),
                ]), terminal: nil))
        sessions.apply(ask, at: now)
        sessions.markHeld(["s"])
        var session = try XCTUnwrap(sessions.session("s"))
        XCTAssertTrue(session.heldAtCap)
        XCTAssertEqual(SessionSwitcher.status(session), "Paused at spend cap")
        XCTAssertEqual(session.stateLabel, "Paused at spend cap")
        sessions.markHeld([])
        session = try XCTUnwrap(sessions.session("s"))
        XCTAssertFalse(session.heldAtCap)
        XCTAssertEqual(SessionSwitcher.status(session), "Needs approval")
        XCTAssertEqual(session.stateLabel, "Approve?")
    }

    func testTheSwitcherMovesOffAShelfShortcutThatTakesIt() {
        XCTAssertEqual(Hotkey.switcherShortcut(shelf: .hyperSpace), Hotkey.switcherHyper)
        XCTAssertEqual(Hotkey.switcherShortcut(shelf: Hotkey.switcherHyper), Hotkey.switcherFallback)
        // Without Hyper the switcher always has ⌃⌥⌘G.
        let plain = Hotkey(keyCode: KeyCodes.space, modifiers: [.option])
        XCTAssertEqual(Hotkey.switcherShortcut(shelf: plain), Hotkey.switcherFallback)
        XCTAssertFalse(Hotkey.switcherClashes(shelf: .hyperSpace))
        XCTAssertTrue(Hotkey.switcherClashes(shelf: Hotkey.switcherHyper))
        XCTAssertFalse(Hotkey.switcherClashes(shelf: plain))
    }

    func testTheShortcuts() {
        XCTAssertEqual(Hotkey.switcherHyper.keyCode, KeyCodes.g)
        XCTAssertTrue(Hotkey.switcherHyper.usesHyper)
        XCTAssertEqual(Hotkey.switcherFallback.modifiers, [.control, .option, .command])
    }
}
