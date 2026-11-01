import XCTest

@testable import WispCore

final class AgentTimelineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    private func event(_ kind: String, extra: String = "") throws -> AgentEvent {
        try AgentEvent.decode(Data(#"{"session_id":"s","cwd":"/p/app","hook_event_name":"\#(kind)"\#(extra)}"#.utf8))
    }

    func testEventsBecomeTimelineEntries() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("SessionStart"), at: start)
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(
            try event("PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"npm test"}"#),
            at: start)
        sessions.record(.allowed, "Allowed", session: "s", at: start)
        sessions.apply(try event("Stop"), at: start)
        let timeline = try XCTUnwrap(sessions.session("s")?.timeline)
        XCTAssertEqual(timeline.map(\.kind), [.started, .prompt, .request, .allowed, .done])
        XCTAssertEqual(timeline[2].display(hidden: false), "Bash: npm test")
        XCTAssertEqual(timeline[2].display(hidden: true), "Bash")
        XCTAssertEqual(timeline[0].display(hidden: true), "Session started")
    }

    func testTimelineIsCapped() throws {
        var sessions = AgentSessions()
        for _ in 0..<60 { sessions.apply(try event("UserPromptSubmit"), at: start) }
        XCTAssertEqual(sessions.session("s")?.timeline.count, AgentSessions.timelineLimit)
    }

    func testAllowAllLastsUntilTheSessionEnds() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("SessionStart"), at: start)
        XCTAssertFalse(sessions.shouldAutoApprove("s"))
        sessions.allowAll(session: "s")
        XCTAssertTrue(sessions.shouldAutoApprove("s"))
        sessions.apply(try event("SessionEnd"), at: start)
        XCTAssertFalse(sessions.shouldAutoApprove("s"))
    }
}

final class DailySpendTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private let day = Date(timeIntervalSince1970: 1_793_350_800)

    func testAddsUpByDay() {
        var spend = DailySpend()
        spend.add(0.4, on: day, calendar: calendar)
        spend.add(0.35, on: day.addingTimeInterval(3_600), calendar: calendar)
        spend.add(2, on: day.addingTimeInterval(-86_400), calendar: calendar)
        XCTAssertEqual(spend.total(on: day, calendar: calendar), 0.75, accuracy: 1e-9)
        XCTAssertEqual(spend.total(on: day.addingTimeInterval(-86_400), calendar: calendar), 2, accuracy: 1e-9)
    }

    func testIgnoresRefundsAndKeepsAMonth() {
        var spend = DailySpend()
        spend.add(-1, on: day, calendar: calendar)
        XCTAssertEqual(spend.total(on: day, calendar: calendar), 0)
        for offset in 0..<40 { spend.add(1, on: day.addingTimeInterval(Double(-offset) * 86_400), calendar: calendar) }
        XCTAssertEqual(spend.days.count, DailySpend.keptDays)
    }

    func testRecentDaysOldestFirstWithGaps() {
        var spend = DailySpend()
        spend.add(1, on: day, calendar: calendar)
        spend.add(3, on: day.addingTimeInterval(-2 * 86_400), calendar: calendar)
        spend.add(9, on: day.addingTimeInterval(-7 * 86_400), calendar: calendar)
        XCTAssertEqual(spend.recent(days: 7, ending: day, calendar: calendar), [0, 0, 0, 0, 3, 0, 1])
        XCTAssertEqual(spend.total(lastDays: 7, ending: day, calendar: calendar), 4, accuracy: 1e-9)
        XCTAssertEqual(spend.total(lastDays: 8, ending: day, calendar: calendar), 13, accuracy: 1e-9)
    }

    func testRecentDaysCrossAMonthAndCanBeEmpty() {
        var spend = DailySpend()
        let firstOfMonth = Date(timeIntervalSince1970: 1_793_491_200)  // 1 Nov 2026, UTC
        spend.add(2, on: firstOfMonth.addingTimeInterval(-86_400), calendar: calendar)
        XCTAssertEqual(spend.recent(days: 3, ending: firstOfMonth, calendar: calendar), [0, 2, 0])
        XCTAssertEqual(DailySpend().recent(days: 7, ending: day, calendar: calendar), Array(repeating: 0, count: 7))
        XCTAssertEqual(spend.recent(days: 0, ending: day, calendar: calendar), [])
    }

    func testRoundTripsThroughJSON() throws {
        var spend = DailySpend()
        spend.add(1.5, on: day, calendar: calendar)
        let decoded = try JSONDecoder().decode(DailySpend.self, from: JSONEncoder().encode(spend))
        XCTAssertEqual(decoded.total(on: day, calendar: calendar), 1.5)
    }

    func testOldSavedSpendStillLoads() throws {
        let old = Data(#"{"days":{"2026-10-31":2.5}}"#.utf8)
        let decoded = try JSONDecoder().decode(DailySpend.self, from: old)
        XCTAssertEqual(decoded.days["2026-10-31"], 2.5)
        XCTAssertEqual(decoded.byProject(lastDays: 7, ending: day, calendar: calendar).map(\.project), [])
    }

    func testSpendByProjectWithOtherForUnattributed() {
        var spend = DailySpend()
        spend.add(1, on: day, project: "wisp", calendar: calendar)
        spend.add(3, on: day.addingTimeInterval(-86_400), project: "site", calendar: calendar)
        spend.add(0.5, on: day, project: "site", calendar: calendar)
        spend.add(0.25, on: day, calendar: calendar)
        spend.add(9, on: day.addingTimeInterval(-8 * 86_400), project: "old", calendar: calendar)
        let rows = spend.byProject(lastDays: 7, ending: day, calendar: calendar)
        XCTAssertEqual(rows.map(\.project), ["site", "wisp", DailySpend.otherProjects])
        XCTAssertEqual(rows[0].today, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rows[0].week, 3.5, accuracy: 1e-9)
        XCTAssertEqual(rows[2].week, 0.25, accuracy: 1e-9)
        XCTAssertEqual(
            rows.map(\.week).reduce(0, +), spend.total(lastDays: 7, ending: day, calendar: calendar), accuracy: 1e-9)
    }

    func testTopFoldsTheRestIntoOther() {
        var spend = DailySpend()
        for (index, name) in ["a", "b", "c", "d"].enumerated() {
            spend.add(Double(10 - index), on: day, project: name, calendar: calendar)
        }
        spend.add(0.5, on: day, calendar: calendar)
        let rows = spend.byProject(lastDays: 7, ending: day, top: 2, calendar: calendar)
        XCTAssertEqual(rows.map(\.project), ["a", "b", DailySpend.otherProjects])
        XCTAssertEqual(rows[2].week, 8 + 7 + 0.5, accuracy: 1e-9)
        // One row past the top isn't worth folding.
        XCTAssertEqual(spend.byProject(lastDays: 7, ending: day, top: 4, calendar: calendar).count, 5)
    }

    func testProjectEntriesArePrunedWithTheirDays() throws {
        var spend = DailySpend()
        for offset in 0..<40 {
            spend.add(1, on: day.addingTimeInterval(Double(-offset) * 86_400), project: "p", calendar: calendar)
        }
        XCTAssertEqual(spend.projects.count, DailySpend.keptDays)
        XCTAssertEqual(Set(spend.projects.keys), Set(spend.days.keys))
        let decoded = try JSONDecoder().decode(DailySpend.self, from: JSONEncoder().encode(spend))
        XCTAssertEqual(decoded, spend)
    }
}

final class SpendLedgerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    func testOnlyTheIncreaseIsNew() {
        var ledger = SpendLedger()
        XCTAssertEqual(ledger.record(total: 1.5, for: "/t/a.jsonl", at: start), 1.5)
        XCTAssertEqual(ledger.record(total: 2.0, for: "/t/a.jsonl", at: start), 0.5)
        XCTAssertEqual(ledger.record(total: 0.25, for: "/t/b.jsonl", at: start), 0.25)
    }

    func testReadingATranscriptAgainAddsNothing() {
        var ledger = SpendLedger()
        _ = ledger.record(total: 3, for: "/t/a.jsonl", at: start)
        XCTAssertEqual(ledger.record(total: 3, for: "/t/a.jsonl", at: start.addingTimeInterval(7 * 3600)), 0)
        XCTAssertEqual(ledger.record(total: 2, for: "/t/a.jsonl", at: start), 0, "a partial read never goes negative")
        XCTAssertEqual(ledger.counted(for: "/t/a.jsonl"), 3)
    }

    func testSurvivesARelaunch() throws {
        var ledger = SpendLedger()
        _ = ledger.record(total: 4, for: "/t/a.jsonl", at: start)
        var decoded = try JSONDecoder().decode(SpendLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded.record(total: 4.5, for: "/t/a.jsonl", at: start), 0.5)
    }

    func testOldTranscriptsAreForgotten() {
        var ledger = SpendLedger()
        _ = ledger.record(total: 4, for: "/t/old.jsonl", at: start)
        _ = ledger.record(total: 1, for: "/t/new.jsonl", at: start.addingTimeInterval(SpendLedger.keptSeconds))
        XCTAssertEqual(ledger.counted(for: "/t/old.jsonl"), 0)
        XCTAssertEqual(ledger.counted(for: "/t/new.jsonl"), 1)
    }

    func testRealCostIsKeptPerSession() {
        var ledger = SpendLedger()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ledger.record(total: 2, session: "a", transcript: "/t", at: now), 2)
        XCTAssertEqual(ledger.record(total: 2.5, session: "a", transcript: "/t", at: now), 0.5)
        // Resumed into the same transcript: the cost starts again and still counts.
        XCTAssertEqual(ledger.record(total: 0.3, session: "b", transcript: "/t", at: now), 0.3)
    }

    func testAResumedSessionKeepingItsIDStartsANewRun() {
        var ledger = SpendLedger()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ledger.record(total: 2.5, session: "a", transcript: "/t", at: now), 2.5)
        XCTAssertEqual(ledger.record(total: 0.3, session: "a", transcript: "/t", at: now), 0.3, accuracy: 1e-9)
        XCTAssertEqual(ledger.record(total: 0.5, session: "a", transcript: "/t", at: now), 0.2, accuracy: 1e-9)
    }

    func testRealCostBelowTheEstimateUsesUpTheCreditFirst() {
        var ledger = SpendLedger()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ledger.record(total: 1, for: "/t", at: now), 1)
        XCTAssertEqual(ledger.record(total: 0.8, session: "a", transcript: "/t", at: now), 0)
        XCTAssertEqual(ledger.record(total: 1.1, session: "a", transcript: "/t", at: now), 0.1, accuracy: 1e-9)
    }

    func testAResumeSeenOnlyByItsHookStillStartsANewRun() {
        var ledger = SpendLedger()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ledger.record(total: 2.5, session: "a", transcript: "/t", at: now), 2.5)
        ledger.startRun(session: "a", at: now)
        // Wisp missed the drop to zero; the first figure it sees is already above the old total.
        XCTAssertEqual(ledger.record(total: 3, session: "a", transcript: "/t", at: now), 3)
    }

    // Pins the saved format on purpose: renaming `entries` or changing how dates encode
    // would lose every user's ledger, not just fail this test.
    func testEntriesSavedBeforeCreditsStillLoad() throws {
        let old = Data(#"{"entries":{"/t":{"cost":1,"seen":0}}}"#.utf8)
        var ledger = try JSONDecoder().decode(SpendLedger.self, from: old)
        XCTAssertEqual(ledger.counted(for: "/t"), 1)
        XCTAssertEqual(
            ledger.record(total: 1.5, session: "a", transcript: "/t", at: Date(timeIntervalSince1970: 1)), 0.5)
    }

    func testEstimateAlreadyCountedIsntCountedAgain() {
        var ledger = SpendLedger()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ledger.record(total: 1, for: "/t", at: now), 1)
        XCTAssertEqual(ledger.record(total: 1.2, session: "a", transcript: "/t", at: now), 0.2, accuracy: 1e-9)
    }
}
