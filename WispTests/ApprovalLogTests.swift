import XCTest

@testable import WispCore

final class ApprovalLogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(
        _ summary: String? = "npm test", tool: String = "Bash", session: String = "s1", project: String = "app",
        outcome: ApprovalOutcome = .allowed, at date: Date? = nil
    ) -> ApprovalRecord {
        ApprovalRecord(
            sessionID: session, project: project, source: .claude, tool: tool, summary: summary, outcome: outcome,
            date: date ?? now)
    }

    func testNewestComeFirst() {
        var log = ApprovalLog()
        log.add(record("first", at: now.addingTimeInterval(-60)), now: now)
        log.add(record("second"), now: now)
        XCTAssertEqual(log.records.map(\.summary), ["second", "first"])
    }

    func testKeepsTheLastTwoHundred() {
        var log = ApprovalLog()
        for index in 0..<210 {
            log.add(record("\(index)", at: now.addingTimeInterval(Double(index))), now: now.addingTimeInterval(300))
        }
        XCTAssertEqual(log.records.count, ApprovalLog.limit)
        XCTAssertEqual(log.records.first?.summary, "209")
        XCTAssertEqual(log.records.last?.summary, "10")
    }

    func testDropsRecordsOlderThanSevenDays() {
        var log = ApprovalLog()
        log.add(record("old", at: now.addingTimeInterval(-8 * 24 * 3600)), now: now)
        log.add(record("recent", at: now.addingTimeInterval(-6 * 24 * 3600)), now: now)
        XCTAssertEqual(log.records.map(\.summary), ["recent"])
    }

    func testSummaryIsMaskedCutToOneLineAndLeftOutWhenHidden() {
        let shown = ApprovalRecord.summary("GITHUB_TOKEN=abc123 gh pr list\nsecond line", hidden: false)
        XCTAssertEqual(shown, "GITHUB_TOKEN=••• gh pr list")
        XCTAssertNil(ApprovalRecord.summary("npm test", hidden: true))
        XCTAssertNil(ApprovalRecord.summary("   ", hidden: false))
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(ApprovalRecord.summary(long, hidden: false)?.count, SessionRecorder.commandLength)
    }

    func testFiltersBySessionAndOutcome() {
        var log = ApprovalLog()
        log.add(record("a", session: "s1", outcome: .allowed), now: now)
        log.add(record("b", session: "s2", outcome: .terminal), now: now)
        log.add(record("c", session: "s1", outcome: .terminal), now: now)
        XCTAssertEqual(log.filtered(session: "s1", outcome: nil).map(\.summary), ["c", "a"])
        XCTAssertEqual(log.filtered(session: nil, outcome: .terminal).map(\.summary), ["c", "b"])
        XCTAssertEqual(log.filtered(session: "s1", outcome: .terminal).map(\.summary), ["c"])
        XCTAssertEqual(log.filtered(session: nil, outcome: nil).count, 3)
    }

    func testSessionsListsEachOnceNewestFirst() {
        var log = ApprovalLog()
        log.add(record(session: "s1", project: "api", at: now.addingTimeInterval(-30)), now: now)
        log.add(record(session: "s2", project: "web", at: now.addingTimeInterval(-20)), now: now)
        log.add(record(session: "s1", project: "api", at: now.addingTimeInterval(-10)), now: now)
        XCTAssertEqual(log.sessions.map(\.id), ["s1", "s2"])
        XCTAssertEqual(log.sessions.map(\.project), ["api", "web"])
    }

    func testRoundTripsAndSkipsBadRecords() throws {
        var log = ApprovalLog()
        log.add(record("kept"), now: now)
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try ApprovalLog.decode(data, now: now), log)

        let mixed =
            Data(
                #"{"version":1,"records":[{"nonsense":true},"#.utf8)
            + (try JSONEncoder().encode(log.records[0])) + Data("]}".utf8)
        XCTAssertEqual(try ApprovalLog.decode(mixed, now: now).records.map(\.summary), ["kept"])
        XCTAssertThrowsError(try ApprovalLog.decode(Data("[]".utf8), now: now))
    }

    func testClear() {
        var log = ApprovalLog()
        log.add(record(session: "s1"), now: now)
        log.add(record(session: "s2"), now: now)
        log.clear()
        XCTAssertTrue(log.records.isEmpty)
    }

    func testOutcomeTitles() {
        XCTAssertEqual(ApprovalOutcome.terminal.title, "Answered in the terminal")
        XCTAssertEqual(ApprovalOutcome.rule.title, "By a rule")
        XCTAssertEqual(ApprovalOutcome.timedOut.title, "Timed out")
        XCTAssertEqual(Set(ApprovalOutcome.allCases.map(\.title)).count, ApprovalOutcome.allCases.count)
    }

    func testRecentToolRequestsSkipQuestionsAndPlans() {
        var log = ApprovalLog()
        log.add(record("q", tool: "AskUserQuestion"), now: now)
        log.add(record("p", tool: "ExitPlanMode"), now: now)
        log.add(record("ls"), now: now)
        XCTAssertEqual(log.recentToolRequests(50).map(\.summary), ["ls"])
    }
}
