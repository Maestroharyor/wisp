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
        XCTAssertEqual(timeline[2].text, "Bash: npm test")
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

    func testRoundTripsThroughJSON() throws {
        var spend = DailySpend()
        spend.add(1.5, on: day, calendar: calendar)
        let decoded = try JSONDecoder().decode(DailySpend.self, from: JSONEncoder().encode(spend))
        XCTAssertEqual(decoded.total(on: day, calendar: calendar), 1.5)
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
}
