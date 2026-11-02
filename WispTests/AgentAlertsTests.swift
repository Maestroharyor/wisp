import XCTest

@testable import WispCore

final class AgentAlertsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)
    private let rules = AgentAlertRules(toolMinutes: 5, tools: true, nudgeMinutes: 3, nudges: true)
    private let off = AgentAlertRules(toolMinutes: 5, nudgeMinutes: 3)

    private func tool(_ id: String?, _ command: String = "npm test", started: TimeInterval = 0) -> ActiveTool {
        let input = ToolInput(command: command)
        return ActiveTool(
            id: id, name: "Bash", shown: ToolLabel.describe(tool: "Bash", input: input, hidden: false),
            hidden: ToolLabel.describe(tool: "Bash", input: input, hidden: true), started: start + started)
    }

    private func session(
        _ id: String = "s", state: AgentSession.State = .running, since: TimeInterval = 0, tools: [ActiveTool] = []
    ) -> AgentSession {
        var session = AgentSession(id: id, project: "api", state: state, turnStarted: start, updated: start)
        session.stateSince = start + since
        session.runningTools = tools
        return session
    }

    func testALongToolAlertsOnceAtItsLimit() {
        var alerts = AgentAlerts()
        let sessions = [session(tools: [tool("t1")])]
        XCTAssertEqual(alerts.due(sessions, rules: rules, now: start + 299), [])
        let fired = alerts.due(sessions, rules: rules, now: start + 300)
        XCTAssertEqual(fired, [.longTool(session: "s", project: "api", tool: tool("t1"), minutes: 5)])
        XCTAssertEqual(alerts.due(sessions, rules: rules, now: start + 900), [], "only once")
    }

    func testParallelToolsAlertSeparately() {
        var alerts = AgentAlerts()
        let sessions = [session(tools: [tool("t1"), tool("t2", started: 60)])]
        XCTAssertEqual(alerts.due(sessions, rules: rules, now: start + 300).count, 1)
        XCTAssertEqual(alerts.due(sessions, rules: rules, now: start + 360).count, 1)
    }

    func testAToolWithoutAnIDIsKeyedByItsStart() {
        var alerts = AgentAlerts()
        XCTAssertEqual(alerts.due([session(tools: [tool(nil)])], rules: rules, now: start + 300).count, 1)
        XCTAssertEqual(alerts.due([session(tools: [tool(nil)])], rules: rules, now: start + 400).count, 0)
        let next = [session(tools: [tool(nil, started: 500)])]
        XCTAssertEqual(alerts.due(next, rules: rules, now: start + 800).count, 1, "a later call is a new tool")
    }

    func testAWaitNudgesOnceAndANewWaitNudgesAgain() {
        var alerts = AgentAlerts()
        let waiting = [session(state: .waiting)]
        XCTAssertEqual(alerts.due(waiting, rules: rules, now: start + 179), [])
        XCTAssertEqual(
            alerts.due(waiting, rules: rules, now: start + 180), [.nudge(session: "s", project: "api", approval: false)]
        )
        XCTAssertEqual(alerts.due(waiting, rules: rules, now: start + 600), [])
        XCTAssertEqual(alerts.due([session(state: .running, since: 600)], rules: rules, now: start + 601), [])
        let again = [session(state: .waiting, since: 700)]
        XCTAssertEqual(alerts.due(again, rules: rules, now: start + 880).count, 1)
    }

    func testAnApprovalWaitIsMarkedAsOne() {
        var alerts = AgentAlerts()
        XCTAssertEqual(
            alerts.due([session(state: .needsApproval)], rules: rules, now: start + 180),
            [.nudge(session: "s", project: "api", approval: true)])
    }

    func testFinishedAndIdleSessionsNeverNudge() {
        var alerts = AgentAlerts()
        let quiet = [session("a", state: .finished), session("b", state: .idle), session("c", state: .running)]
        XCTAssertEqual(alerts.due(quiet, rules: rules, now: start + 3600), [])
    }

    func testARuleThatsOffMarksWithoutAlertingSoTurningItOnStaysQuiet() {
        var alerts = AgentAlerts()
        let sessions = [session(state: .waiting, tools: [tool("t1")])]
        XCTAssertEqual(alerts.due(sessions, rules: off, now: start + 900), [])
        XCTAssertEqual(alerts.due(sessions, rules: rules, now: start + 901), [], "already past when turned on")
        let fresh = [session(tools: [tool("t2", started: 1000)])]
        XCTAssertEqual(alerts.due(fresh, rules: rules, now: start + 1300).count, 1)
    }

    func testARuleTurnedOnBeforeTheLimitStillAlertsAtIt() {
        var alerts = AgentAlerts()
        let sessions = [session(state: .waiting, tools: [tool("t1")])]
        XCTAssertEqual(alerts.due(sessions, rules: off, now: start + 10), [])
        XCTAssertEqual(alerts.nextCheck(sessions, rules: rules, now: start + 10), start + 180)
        XCTAssertEqual(alerts.due(sessions, rules: rules, now: start + 180).count, 1, "the wait")
        XCTAssertEqual(alerts.due(sessions, rules: rules, now: start + 300).count, 1, "the tool")
    }

    func testSeveralLongToolsShareOneNotice() {
        let first = AgentAlert.longTool(session: "a", project: "api", tool: tool("1"), minutes: 5)
        let second = AgentAlert.longTool(session: "b", project: "web", tool: tool("2", "make"), minutes: 5)
        let nudge = AgentAlert.nudge(session: "c", project: "x", approval: false)
        XCTAssertEqual(AgentAlert.notice([first, nudge, second], hidden: false), "5m · npm test +1")
        XCTAssertEqual(AgentAlert.notice([second], hidden: false), "5m · make")
        XCTAssertNil(AgentAlert.notice([nudge], hidden: false))
    }

    func testKeysForEndedToolsAndWaitsArePruned() {
        var alerts = AgentAlerts()
        _ = alerts.due([session(state: .waiting, tools: [tool("t1")])], rules: rules, now: start + 600)
        XCTAssertEqual(alerts.fired.count, 2)
        _ = alerts.due([session(state: .finished, since: 700)], rules: rules, now: start + 701)
        XCTAssertEqual(alerts.fired, [])
    }

    func testNextCheckIsTheSoonestLimitNotYetReached() {
        var alerts = AgentAlerts()
        let sessions = [session(state: .waiting, since: 100, tools: [tool("t1")])]
        XCTAssertEqual(alerts.nextCheck(sessions, rules: rules, now: start), start + 280)
        _ = alerts.due(sessions, rules: rules, now: start + 280)
        XCTAssertEqual(alerts.nextCheck(sessions, rules: rules, now: start + 280), start + 300)
        _ = alerts.due(sessions, rules: rules, now: start + 300)
        XCTAssertNil(alerts.nextCheck(sessions, rules: rules, now: start + 300))
        XCTAssertNil(AgentAlerts().nextCheck(sessions, rules: off, now: start), "rules off")
        XCTAssertNil(AgentAlerts().nextCheck([session()], rules: rules, now: start), "nothing to wait for")
    }

    func testTheNoticeNamesTheToolUnlessHidden() {
        let alert = AgentAlert.longTool(
            session: "s", project: "api", tool: tool("t", "cat secrets.txt"), minutes: 5)
        XCTAssertEqual(alert.text(hidden: false), "5m · cat secrets.txt")
        XCTAssertEqual(alert.text(hidden: true), "5m · Running")
        XCTAssertNil(AgentAlert.nudge(session: "s", project: "api", approval: false).text(hidden: false))
    }
}

final class AgentReminderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    private func event(_ id: String, _ name: String, extra: String = "") throws -> AgentEvent {
        try AgentEvent.decode(Data(#"{"session_id":"\#(id)","hook_event_name":"\#(name)"\#(extra)}"#.utf8))
    }

    func testAReminderPutsAWaitingSessionBackInThePillForAMoment() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("wait", "UserPromptSubmit"), at: start)
        sessions.apply(try event("wait", "Notification", extra: #","notification_type":"idle_prompt""#), at: start + 1)
        sessions.apply(try event("busy", "UserPromptSubmit"), at: start + 2)
        XCTAssertEqual(sessions.session("wait")?.state, .waiting)
        XCTAssertEqual(AgentUrgency.pick(sessions.list, now: start + 100).primary?.id, "busy")

        sessions.nudge(session: "wait", at: start + 180)
        XCTAssertEqual(AgentUrgency.pick(sessions.list, now: start + 181).primary?.id, "wait")
        XCTAssertEqual(AgentUrgency.momentEnds(sessions.list, now: start + 181), start + 184)
        XCTAssertEqual(AgentUrgency.pick(sessions.list, now: start + 185).primary?.id, "busy")
    }

    func testOnlyAWaitingSessionCanBeReminded() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("busy", "UserPromptSubmit"), at: start)
        sessions.nudge(session: "busy", at: start + 10)
        XCTAssertNil(sessions.session("busy")?.nudged)
    }

    func testAnAnsweredApprovalStartsANewState() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("s", "UserPromptSubmit"), at: start)
        sessions.apply(try event("s", "PermissionRequest", extra: #","tool_name":"Bash""#), at: start + 1)
        sessions.resolveApproval(session: "s", at: start + 50)
        XCTAssertEqual(sessions.session("s")?.state, .running)
        XCTAssertEqual(sessions.session("s")?.stateSince, start + 50)
    }
}

final class SpendBudgetTests: XCTestCase {
    func testLevelsFireAtEightyAndOneHundredPercent() {
        XCTAssertNil(SpendBudget.alert(spent: 15.8, budget: 20, fired: nil))
        XCTAssertEqual(SpendBudget.alert(spent: 16, budget: 20, fired: nil), .warning)
        XCTAssertNil(SpendBudget.alert(spent: 19, budget: 20, fired: .warning))
        XCTAssertEqual(SpendBudget.alert(spent: 20, budget: 20, fired: .warning), .reached)
        XCTAssertNil(SpendBudget.alert(spent: 40, budget: 20, fired: .reached))
    }

    func testAJumpPastTheBudgetGivesOnlyTheLastLevel() {
        XCTAssertEqual(SpendBudget.alert(spent: 24, budget: 20, fired: nil), .reached)
    }

    func testNoBudgetNeverAlerts() {
        XCTAssertNil(SpendBudget.alert(spent: 100, budget: 0, fired: nil))
        XCTAssertNil(SpendBudget.alert(spent: 100, budget: -5, fired: nil))
    }

    func testWhatFiredIsForgottenOnANewDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        var state = SpendBudget.State()
        XCTAssertNil(state.fired(on: day, budget: 20, calendar: calendar))
        state.record(.warning, on: day, budget: 20, calendar: calendar)
        XCTAssertEqual(state.fired(on: day + 60, budget: 20, calendar: calendar), .warning)
        XCTAssertNil(state.fired(on: day + 86_400, budget: 20, calendar: calendar))
    }

    func testRaisingTheBudgetAlertsAgainAtTheNewLevels() {
        var state = SpendBudget.State()
        state.record(.reached, on: .now, budget: 20)
        let fired = state.fired(on: .now, budget: 40)
        XCTAssertNil(fired)
        XCTAssertEqual(SpendBudget.alert(spent: 33, budget: 40, fired: fired), .warning)
    }

    func testTheStateSurvivesSaving() throws {
        var state = SpendBudget.State()
        state.record(.reached, on: .now, budget: 20)
        let decoded = try JSONDecoder().decode(SpendBudget.State.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
        let empty = try JSONDecoder().decode(SpendBudget.State.self, from: Data(#"{"day":""}"#.utf8))
        XCTAssertNil(empty.fired)
        XCTAssertNil(empty.budget)
    }

    func testNoticesReadPlainly() {
        XCTAssertEqual(SpendBudget.text(level: .warning, budget: 20), "80% of $20")
        XCTAssertEqual(SpendBudget.text(level: .reached, budget: 12.5), "Over $12.50")
    }
}
