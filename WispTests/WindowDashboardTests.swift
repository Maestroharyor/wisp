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
