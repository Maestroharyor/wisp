import XCTest

@testable import WispCore

final class IdleNudgeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testWaitsFiveMinutesByDefault() {
        XCTAssertEqual(IdleNudge.defaultMinutes, 5)
        XCTAssertEqual(AgentAlertRules.defaultNudgeMinutes, IdleNudge.defaultMinutes)
    }

    func testText() {
        XCTAssertEqual(IdleNudge.text(agent: "Claude Code", minutes: 5), "Claude Code has waited 5 min")
        XCTAssertEqual(IdleNudge.text(agent: "Codex", minutes: 1), "Codex has waited 1 min")
    }

    func testFiresOncePerWaitAtTheLimit() {
        var alerts = AgentAlerts()
        let rules = AgentAlertRules(nudgeMinutes: 5, nudges: true)
        var session = AgentSession(id: "s", project: "api", state: .needsApproval, turnStarted: start, updated: start)
        session.stateSince = start
        XCTAssertEqual(alerts.due([session], rules: rules, now: start + 299), [])
        XCTAssertEqual(alerts.nextCheck([session], rules: rules, now: start + 299), start + 300)
        XCTAssertEqual(
            alerts.due([session], rules: rules, now: start + 300),
            [.nudge(session: "s", project: "api", approval: true)])
        XCTAssertEqual(alerts.due([session], rules: rules, now: start + 900), [])
        // A new wait is a new nudge.
        session.stateSince = start + 1000
        XCTAssertEqual(alerts.due([session], rules: rules, now: start + 1300).count, 1)
    }

    func testOffNeverFires() {
        var alerts = AgentAlerts()
        var session = AgentSession(id: "s", project: "api", state: .waiting, turnStarted: start, updated: start)
        session.stateSince = start
        XCTAssertEqual(alerts.due([session], rules: AgentAlertRules(nudgeMinutes: 5), now: start + 600), [])
    }

    func testPhoneMessage() {
        let moment = AgentMoment.waited(session: "s", project: "api", source: .claude, minutes: 5)
        XCTAssertEqual(moment.kind, .needsYou)
        XCTAssertNotEqual(moment.key, AgentMoment.needsYou(session: "s", project: "api", source: .claude).key)
        XCTAssertEqual(moment.notice(hidden: false).message, "Claude Code has waited 5 min in api.")
        XCTAssertEqual(moment.notice(hidden: true).message, "Claude Code has waited 5 min.")
    }
}
