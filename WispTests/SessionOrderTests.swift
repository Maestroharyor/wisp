import XCTest

@testable import WispCore

final class SessionOrderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String, _ state: AgentSession.State, project: String = "app", updated: TimeInterval = 0,
        since: TimeInterval? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id, project: project, state: state, turnStarted: now, updated: now.addingTimeInterval(updated))
        session.stateSince = now.addingTimeInterval(since ?? updated)
        return session
    }

    private func ids(_ sessions: [AgentSession], _ rules: SessionOrder.Rules = .init(), at time: TimeInterval = 0)
        -> [String]
    {
        SessionOrder.arrange(sessions, rules: rules, now: now.addingTimeInterval(time)).map(\.id)
    }

    func testWhatNeedsYouComesFirstThenRunningThenReadyThenDone() {
        let sessions = [
            session("done", .finished, updated: -10), session("run", .running, updated: -20),
            session("ask", .needsApproval, updated: -30), session("idle", .idle, updated: -5),
            session("wait", .waiting, updated: -40),
        ]
        XCTAssertEqual(ids(sessions), ["ask", "wait", "run", "idle", "done"])
    }

    func testNewestFirstWithinAGroup() {
        let sessions = [session("old", .running, updated: -60), session("new", .running, updated: -1)]
        XCTAssertEqual(ids(sessions), ["new", "old"])
    }

    func testPinnedSessionsAndProjectsComeAfterWhatNeedsYou() {
        let sessions = [
            session("run", .running, updated: -1), session("ask", .needsApproval, updated: -50),
            session("pinned", .finished, updated: -100), session("theirs", .idle, project: "api", updated: -90),
        ]
        var rules = SessionOrder.Rules()
        rules.pinnedSessions = ["pinned"]
        rules.pinnedProjects = ["api"]
        XCTAssertEqual(ids(sessions, rules), ["ask", "theirs", "pinned", "run"])
        XCTAssertTrue(rules.isPinned(sessions[2]))
        XCTAssertTrue(rules.isPinned(sessions[3]))
        XCTAssertFalse(rules.isPinned(sessions[0]))
    }

    func testAHiddenProjectStaysHidden() {
        var rules = SessionOrder.Rules()
        rules.hiddenProjects = ["api"]
        let sessions = [session("a", .needsApproval, project: "api"), session("b", .running)]
        XCTAssertEqual(ids(sessions, rules), ["b"])
    }

    func testAHiddenSessionComesBackWhenItsStateChanges() {
        var rules = SessionOrder.Rules()
        rules.hiddenSessions = ["s": now.addingTimeInterval(-10)]
        XCTAssertEqual(ids([session("s", .finished, since: -20)], rules), [])
        XCTAssertEqual(ids([session("s", .running, since: -5)], rules), ["s"])
    }

    func testDoneSessionsGoAfterTheirKeepTime() {
        let sessions = [session("done", .finished, since: -400), session("run", .running, since: -400)]
        var rules = SessionOrder.Rules()
        rules.keepDone = .fiveMinutes
        XCTAssertEqual(ids(sessions, rules), ["run"])
        rules.keepDone = .oneHour
        XCTAssertEqual(ids(sessions, rules), ["run", "done"])
        rules.keepDone = .untilDismissed
        XCTAssertEqual(ids(sessions, rules, at: 86_400), ["run", "done"])
        // A pinned session stays however long it has been done.
        rules.keepDone = .fiveMinutes
        rules.pinnedSessions = ["done"]
        XCTAssertEqual(ids(sessions, rules), ["done", "run"])
    }

    func testKeepTimes() {
        XCTAssertEqual(SessionOrder.KeepDone.fiveMinutes.interval, 300)
        XCTAssertEqual(SessionOrder.KeepDone.oneHour.interval, 3600)
        XCTAssertNil(SessionOrder.KeepDone.untilDismissed.interval)
    }

    func testHidingKeepsOnlyTheNewestSessions() {
        var hidden: [String: Date] = [:]
        for index in 0..<(SessionOrder.hiddenLimit + 5) {
            hidden = SessionOrder.hiding("s\(index)", at: now.addingTimeInterval(Double(index)), in: hidden)
        }
        XCTAssertEqual(hidden.count, SessionOrder.hiddenLimit)
        XCTAssertNil(hidden["s0"])
        XCTAssertNotNil(hidden["s\(SessionOrder.hiddenLimit + 4)"])
    }
}
