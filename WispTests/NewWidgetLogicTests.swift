import CoreGraphics
import XCTest

@testable import WispCore

final class ColorHexTests: XCTestCase {
    func testFormatsSRGBComponents() {
        XCTAssertEqual(ColorHex.string(red: 1, green: 0, blue: 0), "#FF0000")
        XCTAssertEqual(ColorHex.string(red: 0.2, green: 0.4, blue: 0.6), "#336699")
    }

    func testClampsOutOfGamutValues() {
        XCTAssertEqual(ColorHex.string(red: 1.3, green: -0.2, blue: 0.5), "#FF0080")
    }
}

final class ShortcutListTests: XCTestCase {
    func testParsesOneNamePerLineAndDropsBlanks() {
        XCTAssertEqual(
            ShortcutList.parse("Focus on\n\n  Text Mom \nResize Images\n"), ["Focus on", "Text Mom", "Resize Images"])
    }

    func testDropsDuplicates() {
        XCTAssertEqual(ShortcutList.parse("A\nB\nA"), ["A", "B"])
    }

    func testFavouritesKeepTheirOrderAndSkipMissing() {
        XCTAssertEqual(ShortcutList.favourites(["B", "X", "A"], available: ["A", "B", "C"]), ["B", "A"])
    }
}

final class DayProgressTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: hour, minute: minute)) ?? .distantPast
    }

    func testFractionWithinTheWorkDay() {
        let day = DayProgress(startHour: 9, endHour: 17, calendar: calendar)
        XCTAssertEqual(day.fraction(at: date(9)), 0)
        XCTAssertEqual(day.fraction(at: date(13)), 0.5)
        XCTAssertEqual(day.fraction(at: date(17)), 1)
    }

    func testFractionIsClampedOutsideTheDay() {
        let day = DayProgress(startHour: 9, endHour: 17, calendar: calendar)
        XCTAssertEqual(day.fraction(at: date(6)), 0)
        XCTAssertEqual(day.fraction(at: date(22)), 1)
    }

    func testRemainingMinutes() {
        let day = DayProgress(startHour: 9, endHour: 17, calendar: calendar)
        XCTAssertEqual(day.minutesLeft(at: date(15, 30)), 90)
        XCTAssertEqual(day.minutesLeft(at: date(18)), 0)
    }

    func testMarksAreClampedAndDropEventsOutsideTheDay() {
        let day = DayProgress(startHour: 9, endHour: 17, calendar: calendar)
        let marks = day.marks(for: [date(7)...date(8), date(8)...date(10), date(13)...date(14)], on: date(12))
        XCTAssertEqual(marks, [0...0.125, 0.5...0.625])
    }

    func testInvalidHoursFallBackToADefaultDay() {
        let day = DayProgress(startHour: 18, endHour: 9, calendar: calendar)
        XCTAssertEqual(day.startHour, 9)
        XCTAssertEqual(day.endHour, 17)
    }

    private func newYork(_ month: Int, _ day: Int, _ hour: Int) throws -> (Calendar, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        return (calendar, date)
    }

    func testClocksGoingForwardKeepLocalHours() throws {
        let (calendar, onePM) = try newYork(3, 8, 13)
        let day = DayProgress(startHour: 9, endHour: 17, calendar: calendar)
        XCTAssertEqual(day.fraction(at: onePM), 0.5)
        XCTAssertEqual(day.minutesLeft(at: onePM), 240)
    }

    func testClocksGoingBackKeepLocalHours() throws {
        let (calendar, onePM) = try newYork(11, 1, 13)
        let day = DayProgress(startHour: 9, endHour: 17, calendar: calendar)
        XCTAssertEqual(day.fraction(at: onePM), 0.5)
        XCTAssertEqual(day.minutesLeft(at: onePM), 240)
    }

    func testADayEndingAtMidnight() throws {
        let (calendar, sixPM) = try newYork(3, 8, 18)
        let day = DayProgress(startHour: 12, endHour: 24, calendar: calendar)
        XCTAssertEqual(day.fraction(at: sixPM), 0.5)
    }
}

final class WorldClockTests: XCTestCase {
    func testOffsetLabelRelativeToHome() {
        XCTAssertEqual(WorldClock.offsetLabel(seconds: 0), "Same time")
        XCTAssertEqual(WorldClock.offsetLabel(seconds: 3600), "+1h")
        XCTAssertEqual(WorldClock.offsetLabel(seconds: -5 * 3600), "−5h")
        XCTAssertEqual(WorldClock.offsetLabel(seconds: 19800), "+5h 30m")
        XCTAssertEqual(WorldClock.offsetLabel(seconds: -9000), "−2h 30m")
    }

    func testCityNameFromIdentifier() {
        XCTAssertEqual(WorldClock.cityName("America/New_York"), "New York")
        XCTAssertEqual(WorldClock.cityName("Africa/Lagos"), "Lagos")
        XCTAssertEqual(WorldClock.cityName("UTC"), "UTC")
    }

    func testDaytime() {
        XCTAssertTrue(WorldClock.isDaytime(hour: 7))
        XCTAssertTrue(WorldClock.isDaytime(hour: 18))
        XCTAssertFalse(WorldClock.isDaytime(hour: 19))
        XCTAssertFalse(WorldClock.isDaytime(hour: 5))
    }
}
