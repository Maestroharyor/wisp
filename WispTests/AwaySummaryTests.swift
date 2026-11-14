import XCTest

@testable import WispCore

final class AwaySummaryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var end: Date { start.addingTimeInterval(3600) }
    private var away: DateInterval { DateInterval(start: start, end: end) }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func record(
        _ session: String, ended: Date, waiting: Bool = false, exited: Bool? = nil
    ) -> SessionRecord {
        var record = SessionRecord(
            sessionID: session, project: "wisp", source: .claude, started: start.addingTimeInterval(-600), ended: ended,
            turns: 1, endedWaiting: waiting)
        record.exited = exited
        return record
    }

    private func approval(_ session: String, _ outcome: ApprovalOutcome, at date: Date) -> ApprovalRecord {
        ApprovalRecord(
            sessionID: session, project: "wisp", source: .claude, tool: "Bash", summary: nil, outcome: outcome,
            date: date)
    }

    // MARK: Counting

    func testCountsWhatEndedWhileAway() {
        let records = [
            record("a", ended: start.addingTimeInterval(60)),
            record("b", ended: start.addingTimeInterval(120)),
            record("c", ended: start.addingTimeInterval(180)),
            record("d", ended: start.addingTimeInterval(240), exited: true),
            // Before and after the away time.
            record("e", ended: start.addingTimeInterval(-60)),
            record("f", ended: end.addingTimeInterval(60)),
        ]
        let summary = AwaySummary.build(
            records: records, approvals: [], waiting: ["g"], spend: 2.1, during: away)
        XCTAssertEqual(summary, AwaySummary(finished: 3, failed: 1, needsYou: 1, spend: 2.1))
        XCTAssertEqual(summary.text, "While you were away: 3 finished, 1 failed, 1 needs you, $2.10")
    }

    func testARunThatEndedWaitingIsntFinished() {
        let summary = AwaySummary.build(
            records: [record("a", ended: start.addingTimeInterval(60), waiting: true)], approvals: [], waiting: ["a"],
            spend: 0, during: away)
        XCTAssertEqual(summary, AwaySummary(finished: 0, failed: 0, needsYou: 1, spend: 0))
    }

    func testTimedOutRequestsNeedYouOncePerSession() {
        let approvals = [
            approval("a", .timedOut, at: start.addingTimeInterval(60)),
            approval("a", .timedOut, at: start.addingTimeInterval(90)),
            approval("b", .timedOut, at: start.addingTimeInterval(100)),
            approval("c", .allowed, at: start.addingTimeInterval(100)),
            approval("d", .timedOut, at: start.addingTimeInterval(-100)),
        ]
        let summary = AwaySummary.build(records: [], approvals: approvals, waiting: ["b"], spend: 0, during: away)
        XCTAssertEqual(summary.needsYou, 2)
    }

    func testNothingHappenedIsEmpty() {
        let summary = AwaySummary.build(records: [], approvals: [], waiting: [], spend: 0.001, during: away)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertFalse(AwaySummary(finished: 0, failed: 0, needsYou: 0, spend: 0.5).isEmpty)
    }

    func testDetailLeavesOutZeros() {
        XCTAssertEqual(AwaySummary(finished: 1, failed: 0, needsYou: 0, spend: 0).detail, "1 finished")
        XCTAssertEqual(AwaySummary(finished: 0, failed: 2, needsYou: 0, spend: 0.4).detail, "2 failed, $0.40")
        XCTAssertEqual(AwaySummary(finished: 0, failed: 0, needsYou: 3, spend: 0).detail, "3 need you")
        XCTAssertEqual(AwaySummary(finished: 0, failed: 0, needsYou: 0, spend: 12).detail, "$12.00")
    }

    func testRecordsSavedBeforeExitedStillLoad() throws {
        let data = try JSONEncoder().encode(record("a", ended: start))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("exited"))
        XCTAssertNil(try JSONDecoder().decode(SessionRecord.self, from: data).exited)
        let failed = try JSONEncoder().encode(record("a", ended: start, exited: true))
        XCTAssertEqual(try JSONDecoder().decode(SessionRecord.self, from: failed).exited, true)
    }

    // MARK: Spend

    func testSpendWithinOneDay() {
        var spend = DailySpend()
        spend.add(1, on: start, calendar: calendar)
        let baseline = SpendBaseline(date: start, total: spend.total(on: start, calendar: calendar))
        spend.add(2.5, on: start.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(AwaySummary.spent(spend, since: baseline, now: end, calendar: calendar), 2.5, accuracy: 0.001)
    }

    func testSpendAcrossMidnight() throws {
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23)))
        let morning = evening.addingTimeInterval(8 * 3600)
        var spend = DailySpend()
        spend.add(4, on: evening, calendar: calendar)
        let baseline = SpendBaseline(date: evening, total: 4)
        spend.add(1, on: evening.addingTimeInterval(1800), calendar: calendar)
        spend.add(2, on: morning, calendar: calendar)
        XCTAssertEqual(AwaySummary.spent(spend, since: baseline, now: morning, calendar: calendar), 3, accuracy: 0.001)
    }

    func testSamplesGiveTheBaselineFromWhenTheAwayTimeStarted() {
        var samples = SpendSamples()
        XCTAssertNil(samples.baseline(at: start))
        samples.record(total: 1, at: start.addingTimeInterval(-120))
        samples.record(total: 2, at: start.addingTimeInterval(-60))
        samples.record(total: 3, at: start.addingTimeInterval(60))
        XCTAssertEqual(samples.baseline(at: start), SpendBaseline(date: start.addingTimeInterval(-60), total: 2))
        // Older than any sample: the oldest is the best guess.
        XCTAssertEqual(
            samples.baseline(at: start.addingTimeInterval(-3600)),
            SpendBaseline(date: start.addingTimeInterval(-120), total: 1))
    }

    func testSamplesKeepOnlyTheLastHalfHour() {
        var samples = SpendSamples()
        samples.record(total: 1, at: start)
        samples.record(total: 2, at: start.addingTimeInterval(SpendSamples.kept + 60))
        XCTAssertEqual(samples.count, 1)
    }

    // MARK: Tracker

    func testIdleForFifteenMinutesThenBack() {
        var tracker = AwayTracker()
        XCTAssertNil(tracker.handle(.idle(600), at: start))
        XCTAssertNil(tracker.since)
        XCTAssertNil(tracker.handle(.idle(AwayTracker.minimum), at: start))
        XCTAssertEqual(tracker.since, start.addingTimeInterval(-AwayTracker.minimum))
        XCTAssertTrue(tracker.isIdleAway)
        let back = start.addingTimeInterval(600)
        XCTAssertEqual(
            tracker.handle(.idle(5), at: back),
            DateInterval(start: start.addingTimeInterval(-AwayTracker.minimum), end: back))
        XCTAssertNil(tracker.since)
    }

    func testShortLockIsntAway() {
        var tracker = AwayTracker()
        XCTAssertNil(tracker.handle(.locked, at: start))
        XCTAssertNil(tracker.handle(.unlocked, at: start.addingTimeInterval(300)))
        XCTAssertNil(tracker.since)
    }

    func testLongLockIsAway() {
        var tracker = AwayTracker()
        _ = tracker.handle(.locked, at: start)
        // Typing the password while locked doesn't count as being back.
        XCTAssertNil(tracker.handle(.idle(1), at: end.addingTimeInterval(-5)))
        XCTAssertFalse(tracker.isIdleAway)
        XCTAssertEqual(tracker.handle(.unlocked, at: end), away)
    }

    func testSleepThenWakeToTheLockScreen() {
        var tracker = AwayTracker()
        _ = tracker.handle(.locked, at: start)
        _ = tracker.handle(.slept, at: start.addingTimeInterval(10))
        XCTAssertNil(tracker.handle(.woke, at: end.addingTimeInterval(-30)))
        XCTAssertEqual(tracker.handle(.unlocked, at: end), away)
    }

    func testWakeWithoutALockIsBack() {
        var tracker = AwayTracker()
        _ = tracker.handle(.slept, at: start)
        XCTAssertEqual(tracker.handle(.woke, at: end), away)
    }

    func testIdleBeforeALockKeepsTheEarlierStart() {
        var tracker = AwayTracker()
        _ = tracker.handle(.idle(AwayTracker.minimum), at: start.addingTimeInterval(AwayTracker.minimum))
        _ = tracker.handle(.locked, at: start.addingTimeInterval(1200))
        XCTAssertEqual(tracker.handle(.unlocked, at: end), away)
    }

    func testBackWithoutBeingAwayIsNothing() {
        var tracker = AwayTracker()
        XCTAssertNil(tracker.handle(.unlocked, at: start))
        XCTAssertNil(tracker.handle(.woke, at: start))
        XCTAssertNil(tracker.handle(.idle(0), at: start))
    }
}
