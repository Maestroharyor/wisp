import XCTest

@testable import WispCore

final class CalendarDaysTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    // Friday 30 October 2026, 09:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_350_800)

    func testLabels() {
        XCTAssertEqual(CalendarDays.label(for: now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(
            CalendarDays.label(for: now.addingTimeInterval(86_400), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(
            CalendarDays.label(for: now.addingTimeInterval(3 * 86_400), now: now, calendar: calendar), "Mon 2")
    }

    func testGroupsByDayInOrder() {
        let dates = [
            now.addingTimeInterval(86_400), now, now.addingTimeInterval(3_600), now.addingTimeInterval(3 * 86_400),
        ]
        let days = CalendarDays.group(dates, date: { $0 }, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.label), ["Today", "Tomorrow", "Mon 2"])
        XCTAssertEqual(days.first?.items.count, 2)
    }
}
