import Foundation
import XCTest

@testable import WispCore

final class ReminderListTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }
    // 2026-11-20 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_763_640_000)

    private func item(_ title: String, due: TimeInterval?, done: Bool = false) -> ReminderItem {
        ReminderItem(id: title, title: title, due: due.map { now.addingTimeInterval($0) }, isCompleted: done)
    }

    func testOverdueThenTodayThenLaterThenUndated() {
        let items = [
            item("someday", due: nil), item("next week", due: 7 * 86_400), item("tonight", due: 6 * 3_600),
            item("yesterday", due: -86_400), item("this morning", due: -3 * 3_600),
        ]
        let ordered = ReminderList.ordered(items, now: now, calendar: calendar)
        XCTAssertEqual(ordered.map(\.title), ["yesterday", "this morning", "tonight", "next week", "someday"])
    }

    func testDoneRemindersAreHidden() {
        let ordered = ReminderList.ordered(
            [item("a", due: nil, done: true), item("b", due: nil)], now: now, calendar: calendar)
        XCTAssertEqual(ordered.map(\.title), ["b"])
    }

    func testOverdueMeansBeforeNow() {
        XCTAssertTrue(ReminderList.isOverdue(item("x", due: -60), now: now))
        XCTAssertFalse(ReminderList.isOverdue(item("x", due: 60), now: now))
        XCTAssertFalse(ReminderList.isOverdue(item("x", due: nil), now: now))
    }

    func testUndatedKeepTheirOrderAndTheListIsCapped() {
        let items = (0..<30).map { item("r\($0)", due: nil) }
        let ordered = ReminderList.ordered(items, now: now, calendar: calendar)
        XCTAssertEqual(ordered.count, ReminderList.limit)
        XCTAssertEqual(ordered.first?.title, "r0")
    }
}

final class PomodoroLabelTests: XCTestCase {
    func testTheFirstLineIsTheLabel() {
        XCTAssertEqual(PomodoroLabel.from("  Write the report \nwith charts"), "Write the report")
    }

    func testLabelsAreShortAndNeverBlank() {
        XCTAssertEqual(PomodoroLabel.from(String(repeating: "a", count: 100))?.count, PomodoroLabel.maxLength)
        XCTAssertNil(PomodoroLabel.from("   \n  "))
    }

    func testSessionsKeepTheirLabel() throws {
        var log = PomodoroLog()
        let end = Date(timeIntervalSince1970: 1_763_640_000)
        log.record(start: end.addingTimeInterval(-1_500), end: end, label: "Report")
        XCTAssertEqual(log.sessions.last?.label, "Report")
        let decoded = try JSONDecoder().decode(PomodoroLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
    }

    func testYesterdaysSessionsGoWhenTheDayChanges() {
        var log = PomodoroLog()
        let yesterday = Date(timeIntervalSince1970: 1_763_640_000)
        log.record(start: yesterday.addingTimeInterval(-1_500), end: yesterday, label: "Old")
        log.dropOldDays(now: yesterday.addingTimeInterval(86_400))
        XCTAssertTrue(log.sessions.isEmpty)
        log.record(start: yesterday.addingTimeInterval(-1_500), end: yesterday, label: "Today")
        log.dropOldDays(now: yesterday)
        XCTAssertEqual(log.sessions.count, 1)
    }

    func testOldLogsLoadWithoutLabels() throws {
        let old = Data(#"{"sessions":[{"start":0,"end":1500}]}"#.utf8)
        let log = try JSONDecoder().decode(PomodoroLog.self, from: old)
        XCTAssertEqual(log.sessions.count, 1)
        XCTAssertNil(log.sessions.first?.label)
    }
}

final class ClipExtrasTests: XCTestCase {
    func testCopyTogetherJoinsTextInOrder() {
        XCTAssertEqual(ClipMerge.join(["one", "two ", "three"]), "one\ntwo \nthree")
        XCTAssertEqual(ClipMerge.join(["  ", "a"]), "a")
        XCTAssertNil(ClipMerge.join([]))
    }

    func testPasswordAppsAreLeftOutByDefault() {
        XCTAssertFalse(
            ClipClassifier.keeps(from: "com.apple.keychainaccess", excluding: ClipClassifier.defaultExcluded))
        XCTAssertFalse(ClipClassifier.keeps(from: "com.apple.Passwords", excluding: ClipClassifier.defaultExcluded))
        XCTAssertTrue(ClipClassifier.keeps(from: "com.apple.Safari", excluding: ClipClassifier.defaultExcluded))
        XCTAssertTrue(ClipClassifier.keeps(from: nil, excluding: ClipClassifier.defaultExcluded))
    }

    func testExcludedAppsCanBeChosen() {
        XCTAssertFalse(
            ClipClassifier.keeps(from: "com.tinyspeck.slackmacgap", excluding: ["com.tinyspeck.slackmacgap"]))
        XCTAssertTrue(ClipClassifier.keeps(from: "com.apple.keychainaccess", excluding: []))
    }
}
