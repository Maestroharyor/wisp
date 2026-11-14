import XCTest

@testable import WispCore

final class ActivityMapTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    /// Saturday 14 November 2026, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_794_657_600)

    private func record(
        _ session: String, daysAgo: Int, turns: Int, source: AgentSource = .claude, project: String = "app"
    ) -> SessionRecord {
        let started = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return SessionRecord(
            sessionID: session, project: project, source: source, started: started, ended: started + 600,
            turns: turns)
    }

    func testCountsSessionsAndTurnsPerAgentPerDay() {
        var map = ActivityMap()
        map.add(record("a", daysAgo: 0, turns: 3), calendar: calendar)
        map.add(record("b", daysAgo: 0, turns: 5), calendar: calendar)
        map.add(record("c", daysAgo: 0, turns: 2, source: .codex), calendar: calendar)
        map.add(record("d", daysAgo: 1, turns: 1), calendar: calendar)

        let turns = map.breakdown(on: now, metric: .turns, calendar: calendar)
        XCTAssertEqual(turns, [AgentTally(source: .claude, count: 8), AgentTally(source: .codex, count: 2)])
        let sessions = map.breakdown(on: now, metric: .sessions, calendar: calendar)
        XCTAssertEqual(sessions, [AgentTally(source: .claude, count: 2), AgentTally(source: .codex, count: 1)])
        XCTAssertEqual(map.breakdown(on: now - 86_400, metric: .turns, calendar: calendar).first?.count, 1)
    }

    func testKeepsOnlyCounts() throws {
        var map = ActivityMap()
        map.add(record("secret-session", daysAgo: 0, turns: 3, project: "secret-project"), calendar: calendar)
        let text = String(decoding: try JSONEncoder().encode(map), as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertEqual(try JSONDecoder().decode(ActivityMap.self, from: Data(text.utf8)), map)
    }

    func testPruneKeepsTheChosenRetention() {
        var map = ActivityMap()
        map.add(record("recent", daysAgo: 60, turns: 1), calendar: calendar)
        map.add(record("old", daysAgo: 200, turns: 1), calendar: calendar)
        map.add(record("ancient", daysAgo: 500, turns: 1), calendar: calendar)

        var year = map
        year.prune(keeping: .oneYear, now: now, calendar: calendar)
        XCTAssertEqual(year.days.count, 2)
        var quarter = map
        quarter.prune(keeping: .threeMonths, now: now, calendar: calendar)
        XCTAssertEqual(quarter.days.count, 1)
        var two = map
        two.prune(keeping: .twoYears, now: now, calendar: calendar)
        XCTAssertEqual(two.days.count, 3)
    }

    func testGridIs53WeeksEndingInTodaysWeek() throws {
        var map = ActivityMap()
        map.add(record("a", daysAgo: 0, turns: 4), calendar: calendar)
        map.add(record("b", daysAgo: 7, turns: 2, source: .codex), calendar: calendar)
        let grid = map.grid(endingOn: now, metric: .turns, calendar: calendar)

        XCTAssertEqual(grid.columns.count, 53)
        XCTAssertTrue(grid.columns.allSatisfy { $0.count == 7 })
        // Weeks start on Sunday here; today is a Saturday, the last row of the last column.
        let first = try XCTUnwrap(grid.columns.first?.first)
        XCTAssertEqual(calendar.component(.weekday, from: first.date), 1)
        let today = try XCTUnwrap(grid.columns.last?.last)
        XCTAssertTrue(calendar.isDate(today.date, inSameDayAs: now))
        XCTAssertEqual(today.total, 4)
        XCTAssertEqual(grid.total, 6)
        XCTAssertEqual(grid.busiest, 4)
    }

    func testDaysAfterTodayAreFuture() throws {
        var mondayStart = calendar
        mondayStart.firstWeekday = 2
        let grid = ActivityMap().grid(endingOn: now, metric: .sessions, calendar: mondayStart)
        let last = try XCTUnwrap(grid.columns.last)
        // Monday to Saturday so far, Sunday still to come.
        XCTAssertEqual(last.map(\.future), [false, false, false, false, false, false, true])
    }

    func testLevelsStepUpToTheBusiestDay() {
        var map = ActivityMap()
        for (index, turns) in [1, 4, 6, 9, 12].enumerated() {
            map.add(record("s\(index)", daysAgo: index, turns: turns), calendar: calendar)
        }
        let grid = map.grid(endingOn: now, metric: .turns, calendar: calendar)
        let days = grid.columns.joined().filter { $0.total > 0 }.sorted { $0.total < $1.total }
        XCTAssertEqual(days.map(grid.level), [1, 2, 2, 3, 4])
        let empty = grid.columns.joined().first { $0.total == 0 }
        XCTAssertEqual(empty.map(grid.level), 0)
    }

    func testDaySummaryNamesEachAgent() {
        var map = ActivityMap()
        map.add(record("a", daysAgo: 0, turns: 10), calendar: calendar)
        map.add(record("b", daysAgo: 0, turns: 4, source: .codex), calendar: calendar)
        let grid = map.grid(endingOn: now, metric: .turns, calendar: calendar)
        XCTAssertEqual(grid.columns.last?.last?.summary(.turns), "14 turns: Claude Code 10, Codex 4")
        XCTAssertEqual(grid.columns.first?.first?.summary(.sessions), "No sessions")
        XCTAssertEqual(ActivityMetric.sessions.phrase(1), "1 session")
    }

    func testHistoryFoldsDroppedRecordsIntoCounts() {
        var history = SessionHistory()
        let old = record("old", daysAgo: 40, turns: 3)
        history.save(record("new", daysAgo: 1, turns: 2), now: now)
        history.save(old, now: old.ended)
        history.prune(now: now, calendar: calendar)

        XCTAssertEqual(history.records.map(\.sessionID), ["new"])
        let map = history.activityMap(calendar: calendar)
        XCTAssertEqual(map.breakdown(on: old.started, metric: .turns, calendar: calendar).first?.count, 3)
        XCTAssertEqual(map.breakdown(on: now - 86_400, metric: .turns, calendar: calendar).first?.count, 2)
        // The kept record isn't counted twice once it is folded in too.
        XCTAssertEqual(history.activity.days.count, 1)
    }

    func testHistoryFoldsRecordsPastTheCountLimit() {
        var history = SessionHistory()
        for index in 0..<(SessionHistory.limit + 3) {
            history.save(record("s\(index)", daysAgo: 0, turns: 1), now: now)
        }
        let sessions = history.activityMap(calendar: calendar).breakdown(on: now, metric: .sessions, calendar: calendar)
        XCTAssertEqual(sessions.first?.count, SessionHistory.limit + 3)
    }

    func testHistoryKeepsCountsAcrossAFileAndClearRemovesThem() throws {
        var history = SessionHistory()
        let old = record("old", daysAgo: 40, turns: 3)
        history.save(old, now: old.ended)
        history.prune(now: now, calendar: calendar)
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertFalse(history.isEmpty)

        let data = try JSONEncoder().encode(history)
        let loaded = try SessionHistory.decode(data, now: now)
        XCTAssertEqual(loaded.activity, history.activity)

        history.clear()
        XCTAssertTrue(history.isEmpty)
    }

    func testOlderFilesWithoutCountsStillLoad() throws {
        let data = Data(#"{"version":1,"records":[]}"#.utf8)
        XCTAssertTrue(try SessionHistory.decode(data, now: now).activity.isEmpty)
    }

    func testRetentionStartsMonthsBack() {
        let first = ActivityRetention.threeMonths.firstDay(now: now, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: first).month, 8)
        XCTAssertEqual(ActivityRetention.standard, .oneYear)
    }
}
