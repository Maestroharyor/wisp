import XCTest

@testable import WispCore

final class WindowDashboardTests: XCTestCase {
    // MARK: Greeting

    func testTheGreetingFollowsTheHour() {
        XCTAssertEqual(WindowGreeting.greeting(hour: 5), "Good morning")
        XCTAssertEqual(WindowGreeting.greeting(hour: 11), "Good morning")
        XCTAssertEqual(WindowGreeting.greeting(hour: 12), "Good afternoon")
        XCTAssertEqual(WindowGreeting.greeting(hour: 17), "Good evening")
        XCTAssertEqual(WindowGreeting.greeting(hour: 21), "Good evening")
        XCTAssertEqual(WindowGreeting.greeting(hour: 22), "Good night")
        XCTAssertEqual(WindowGreeting.greeting(hour: 0), "Good night")
        XCTAssertEqual(WindowGreeting.greeting(hour: 4), "Good night")
    }

    func testTheGreetingAddsAFirstName() {
        XCTAssertEqual(WindowGreeting.greeting(hour: 9, fullName: "Ada Lovelace"), "Good morning, Ada")
        XCTAssertEqual(WindowGreeting.greeting(hour: 9, fullName: "  "), "Good morning")
    }

    func testEachPartOfTheDayHasItsOwnPalette() {
        let hours = [6, 13, 19, 23]
        let palettes = hours.map { WindowGreeting.palette(hour: $0, isDark: true) }
        XCTAssertEqual(Set(palettes.map(\.leading)).count, hours.count)
    }

    func testLightPalettesAreLighterThanDark() {
        for hour in 0..<24 {
            let light = WindowGreeting.palette(hour: hour, isDark: false)
            let dark = WindowGreeting.palette(hour: hour, isDark: true)
            XCTAssertGreaterThan(light.leading.luminance, dark.leading.luminance, "hour \(hour)")
            XCTAssertGreaterThan(light.trailing.luminance, dark.trailing.luminance, "hour \(hour)")
        }
    }

    func testPaletteColoursStayInRange() {
        for hour in 0..<24 {
            for dark in [true, false] {
                let palette = WindowGreeting.palette(hour: hour, isDark: dark)
                for colour in [palette.leading, palette.trailing] {
                    for channel in [colour.red, colour.green, colour.blue] {
                        XCTAssertTrue((0...1).contains(channel))
                    }
                }
            }
        }
    }

    // MARK: Week strip

    func testTheWeekStripStartsToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 22)))
        let days = WeekStrip.days(from: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, calendar.startOfDay(for: now))
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(days.last)), 27)
        for (earlier, later) in zip(days, days.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: earlier, to: later).day, 1)
        }
    }

    func testSteppingADayStaysInTheStrip() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9)))
        let days = WeekStrip.days(from: now, calendar: calendar)
        // Nil stands for today, the strip's first day.
        XCTAssertEqual(WeekStrip.stepped(nil, by: 1, in: days, calendar: calendar), days[1])
        XCTAssertNil(WeekStrip.stepped(nil, by: -1, in: days, calendar: calendar))
        XCTAssertNil(WeekStrip.stepped(days[1], by: -1, in: days, calendar: calendar))
        XCTAssertEqual(WeekStrip.stepped(days[6], by: 1, in: days, calendar: calendar), days[6])
        XCTAssertEqual(WeekStrip.stepped(days[3], by: 2, in: days, calendar: calendar), days[5])
        // A day outside the strip (left over from yesterday) starts again from today.
        let stale = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: days[0]))
        XCTAssertEqual(WeekStrip.stepped(stale, by: 1, in: days, calendar: calendar), days[1])
    }

    private func utcCalendar(firstWeekday: Int) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    func testTheWeekStartFollowsTheFirstWeekday() throws {
        // Saturday 21 November 2026.
        let monday = try utcCalendar(firstWeekday: 2)
        let saturday = try XCTUnwrap(monday.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 15)))
        let fromMonday = WeekStrip.weekStart(of: saturday, calendar: monday)
        XCTAssertEqual(
            monday.dateComponents([.month, .day, .hour], from: fromMonday), DateComponents(month: 11, day: 16, hour: 0))
        let sunday = try utcCalendar(firstWeekday: 1)
        let fromSunday = WeekStrip.weekStart(of: saturday, calendar: sunday)
        XCTAssertEqual(sunday.dateComponents([.month, .day], from: fromSunday), DateComponents(month: 11, day: 15))
    }

    func testSteppingAWeekCrossesMonthsAndYears() throws {
        let calendar = try utcCalendar(firstWeekday: 2)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 28)))
        let next = WeekStrip.steppedWeek(start, by: 1, calendar: calendar)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: next), DateComponents(year: 2027, month: 1, day: 4))
        let back = WeekStrip.steppedWeek(start, by: -2, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: back), DateComponents(month: 12, day: 14))
    }

    func testTheComingWeekIsTodayAndTheNextSixDays() throws {
        let calendar = try utcCalendar(firstWeekday: 2)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 22)))
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: now) ?? now }
        XCTAssertTrue(WeekStrip.isInComingWeek(day(0), now: now, calendar: calendar))
        XCTAssertTrue(WeekStrip.isInComingWeek(day(6), now: now, calendar: calendar))
        XCTAssertFalse(WeekStrip.isInComingWeek(day(7), now: now, calendar: calendar))
        XCTAssertFalse(WeekStrip.isInComingWeek(day(-1), now: now, calendar: calendar))
    }

    func testTheWeekTitleNamesOtherWeeksByTheirStart() throws {
        let calendar = try utcCalendar(firstWeekday: 2)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9)))
        let thisWeek = WeekStrip.weekStart(of: now, calendar: calendar)
        XCTAssertEqual(WeekStrip.title(weekStart: thisWeek, now: now, calendar: calendar), "This week")
        let later = WeekStrip.steppedWeek(thisWeek, by: 15, calendar: calendar)
        XCTAssertEqual(WeekStrip.title(weekStart: later, now: now, calendar: calendar), "Week of 1 March 2027")
        let soon = WeekStrip.steppedWeek(thisWeek, by: 2, calendar: calendar)
        XCTAssertEqual(WeekStrip.title(weekStart: soon, now: now, calendar: calendar), "Week of 30 November")
    }

    // MARK: Cards

    func testHomeCardsReadWhatWasSaved() {
        XCTAssertEqual(HomeCard.read(nil), HomeCard.standard)
        XCTAssertEqual(HomeCard.read(["notes", "events"]), [.notes, .events])
        XCTAssertEqual(HomeCard.read(["events", "gone", "events", "agents"]), [.events, .agents])
        XCTAssertEqual(HomeCard.read([]), [])
    }

    func testHomeCardsToggleAndMove() {
        let cards: [HomeCard] = [.events, .reminders]
        XCTAssertEqual(HomeCard.toggled(.notes, in: cards), [.events, .reminders, .notes])
        XCTAssertEqual(HomeCard.toggled(.events, in: cards), [.reminders])
        XCTAssertEqual(HomeCard.moved(cards, from: IndexSet(integer: 0), to: 2), [.reminders, .events])
    }

    // MARK: Layout

    func testDashboardColumnsFollowTheWidth() {
        XCTAssertEqual(WindowLayout.dashboardColumns(width: 600), 1)
        XCTAssertEqual(WindowLayout.dashboardColumns(width: 620), 2)
        XCTAssertEqual(WindowLayout.dashboardColumns(width: 979), 2)
        XCTAssertEqual(WindowLayout.dashboardColumns(width: 980), 3)
    }
}
