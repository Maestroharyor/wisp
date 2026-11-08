import XCTest

@testable import WispCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}()

private func date(day: Int = 29, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
}

final class WindowLayoutTests: XCTestCase {
    func testColumnsGrowWithTheWidth() {
        XCTAssertEqual(WindowLayout.columns(width: 200), 1)
        XCTAssertEqual(WindowLayout.columns(width: 460), 2)
        XCTAssertEqual(WindowLayout.columns(width: 500), 2)
        XCTAssertEqual(WindowLayout.columns(width: 740), 3)
        XCTAssertEqual(WindowLayout.columns(width: 1000), 4)
    }

    func testColumnsStopAtTheMaximum() {
        XCTAssertEqual(WindowLayout.columns(width: 2400), 4)
        XCTAssertEqual(WindowLayout.columns(width: 2400, maximum: 6), 6)
    }

    func testColumnsNeverDropBelowOne() {
        XCTAssertEqual(WindowLayout.columns(width: 0), 1)
        XCTAssertEqual(WindowLayout.columns(width: -50), 1)
        XCTAssertEqual(WindowLayout.columns(width: 300, minimum: 0), 1)
    }

    func testCustomCardWidth() {
        XCTAssertEqual(WindowLayout.columns(width: 500, minimum: 150), 3)
    }

    func testTheInspectorShowsOnlyAboveTheThreshold() {
        // The detail beside a 220 pt sidebar at the 720 pt minimum window is 500 pt wide.
        XCTAssertFalse(WindowLayout.showsInspector(width: 500))
        XCTAssertFalse(WindowLayout.showsInspector(width: WindowLayout.inspectorThreshold - 1))
        XCTAssertTrue(WindowLayout.showsInspector(width: WindowLayout.inspectorThreshold))
        XCTAssertTrue(WindowLayout.showsInspector(width: 1200))
    }

    func testReadableWidthCapsWidePages() {
        XCTAssertEqual(WindowLayout.readableWidth(available: 600), 560)
        XCTAssertEqual(WindowLayout.readableWidth(available: 1400), WindowLayout.readableCap)
        XCTAssertEqual(WindowLayout.readableWidth(available: 10), 0)
    }
}

final class KeepAwakeSessionTests: XCTestCase {
    func testIndefiniteSessionNeverExpires() {
        let session = KeepAwakeSession.lasting(nil, from: date(9))
        XCTAssertNil(session.ends)
        XCTAssertNil(session.remaining(now: date(23)))
        XCTAssertFalse(session.isExpired(now: date(day: 30, 9)))
    }

    func testTimedSessionCountsDown() {
        let session = KeepAwakeSession.lasting(3600, from: date(9))
        XCTAssertEqual(session.ends, date(10))
        XCTAssertEqual(session.remaining(now: date(9, 15)), 45 * 60)
        XCTAssertFalse(session.isExpired(now: date(9, 59)))
    }

    func testTimedSessionExpiresAtItsEnd() {
        let session = KeepAwakeSession.lasting(2 * 3600, from: date(9))
        XCTAssertTrue(session.isExpired(now: date(11)))
        XCTAssertTrue(session.isExpired(now: date(12)))
        XCTAssertEqual(session.remaining(now: date(12)), 0)
    }

    func testUntilATimeLaterToday() {
        let session = KeepAwakeSession.until(hour: 15, minute: 40, from: date(9), calendar: utc)
        XCTAssertEqual(session.ends, date(15, 40))
    }

    func testUntilATimeThatHasPassedMeansTomorrow() {
        let session = KeepAwakeSession.until(hour: 8, minute: 0, from: date(9), calendar: utc)
        XCTAssertEqual(session.ends, date(day: 30, 8))
    }

    func testUntilTheCurrentMinuteMeansTomorrow() {
        let session = KeepAwakeSession.until(hour: 9, minute: 0, from: date(9), calendar: utc)
        XCTAssertEqual(session.ends, date(day: 30, 9))
    }

    func testATimeTheCalendarCantFindLastsADay() {
        let session = KeepAwakeSession.until(hour: 25, minute: 0, from: date(9), calendar: utc)
        XCTAssertEqual(session.ends, date(day: 30, 9))
    }

    func testANonPositiveLengthIsIndefinite() {
        XCTAssertNil(KeepAwakeSession.lasting(0, from: date(9)).ends)
        XCTAssertNil(KeepAwakeSession.lasting(-60, from: date(9)).ends)
    }
}

final class PomodoroLogTests: XCTestCase {
    func testRecordsTodaysSessionsInOrder() {
        var log = PomodoroLog()
        log.record(start: date(9), end: date(9, 25), calendar: utc)
        log.record(start: date(10), end: date(10, 50), calendar: utc)
        let today = log.today(now: date(12), calendar: utc)
        XCTAssertEqual(today.map(\.start), [date(9), date(10)])
        XCTAssertEqual(today.map(\.minutes), [25, 50])
        XCTAssertEqual(log.focusMinutes(now: date(12), calendar: utc), 75)
    }

    func testANewDayStartsEmpty() {
        var log = PomodoroLog()
        log.record(start: date(9), end: date(9, 25), calendar: utc)
        XCTAssertTrue(log.today(now: date(day: 30, 8), calendar: utc).isEmpty)
        XCTAssertEqual(log.focusMinutes(now: date(day: 30, 8), calendar: utc), 0)
    }

    func testRecordingOnANewDayDropsYesterday() {
        var log = PomodoroLog()
        log.record(start: date(9), end: date(9, 25), calendar: utc)
        log.record(start: date(day: 30, 9), end: date(day: 30, 9, 25), calendar: utc)
        XCTAssertEqual(log.sessions.count, 1)
        XCTAssertEqual(log.sessions.first?.start, date(day: 30, 9))
    }

    func testASessionCountsOnTheDayItEnded() {
        var log = PomodoroLog()
        log.record(start: date(23, 50), end: date(day: 30, 0, 15), calendar: utc)
        XCTAssertEqual(log.today(now: date(day: 30, 1), calendar: utc).count, 1)
    }

    func testKeepsAtMostFiftySessions() {
        var log = PomodoroLog()
        for index in 0..<60 {
            let start = date(0).addingTimeInterval(TimeInterval(index * 60))
            log.record(start: start, end: start.addingTimeInterval(30), calendar: utc)
        }
        XCTAssertEqual(log.sessions.count, PomodoroLog.limit)
        XCTAssertEqual(log.sessions.first?.start, date(0, 10))
    }

    func testIgnoresAnEndBeforeItsStart() {
        var log = PomodoroLog()
        log.record(start: date(10), end: date(9), calendar: utc)
        XCTAssertTrue(log.sessions.isEmpty)
    }

    func testRoundTripsThroughJSON() throws {
        var log = PomodoroLog()
        log.record(start: date(9), end: date(9, 25), calendar: utc)
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(PomodoroLog.self, from: data), log)
    }
}

final class WorldClockWindowTests: XCTestCase {
    func testShiftSnapsToQuarterHours() {
        XCTAssertEqual(WorldClock.snappedShift(minutes: 7), 0)
        XCTAssertEqual(WorldClock.snappedShift(minutes: 8), 15)
        XCTAssertEqual(WorldClock.snappedShift(minutes: -22), -15)
        XCTAssertEqual(WorldClock.snappedShift(minutes: -23), -30)
        XCTAssertEqual(WorldClock.snappedShift(minutes: 95), 90)
    }

    func testShiftStaysWithinTwelveHours() {
        XCTAssertEqual(WorldClock.snappedShift(minutes: 2000), 720)
        XCTAssertEqual(WorldClock.snappedShift(minutes: -2000), -720)
    }

    func testShiftedTimeFreezesOnTheMinute() {
        let base = date(14, 7).addingTimeInterval(42)
        XCTAssertEqual(WorldClock.shiftedTime(base: base, minutes: 60, calendar: utc), date(15, 7))
        XCTAssertEqual(WorldClock.shiftedTime(base: base, minutes: -15, calendar: utc), date(13, 52))
        XCTAssertEqual(WorldClock.shiftedTime(base: base, minutes: 0, calendar: utc), date(14, 7))
    }

    func testCitiesDropBlanksAndRepeatsAndStopAtEight() {
        let saved = ["Europe/London", "", "Asia/Tokyo", "Europe/London"] + (1...9).map { "Etc/GMT+\($0)" }
        let cities = WorldClock.cities(saved)
        XCTAssertEqual(cities.count, WorldClock.maximumCities)
        XCTAssertEqual(Array(cities.prefix(3)), ["Europe/London", "Asia/Tokyo", "Etc/GMT+1"])
    }

    func testAddingACity() {
        XCTAssertEqual(WorldClock.adding("Asia/Tokyo", to: ["Europe/London"]), ["Europe/London", "Asia/Tokyo"])
        XCTAssertEqual(WorldClock.adding("Europe/London", to: ["Europe/London"]), ["Europe/London"])
        let full = (1...8).map { "Etc/GMT+\($0)" }
        XCTAssertEqual(WorldClock.adding("Asia/Tokyo", to: full), full)
    }

    func testRemovingACity() {
        XCTAssertEqual(WorldClock.removing("Asia/Tokyo", from: ["Europe/London", "", "Asia/Tokyo"]), ["Europe/London"])
    }

    func testMovingACity() {
        let cities = ["A/One", "B/Two", "C/Three"]
        XCTAssertEqual(WorldClock.moving("B/Two", by: -1, in: cities), ["B/Two", "A/One", "C/Three"])
        XCTAssertEqual(WorldClock.moving("B/Two", by: 1, in: cities), ["A/One", "C/Three", "B/Two"])
        XCTAssertEqual(WorldClock.moving("A/One", by: -1, in: cities), cities)
        XCTAssertEqual(WorldClock.moving("C/Three", by: 1, in: cities), cities)
        XCTAssertEqual(WorldClock.moving("Z/None", by: 1, in: cities), cities)
    }

    func testHandAngles() {
        XCTAssertEqual(WorldClock.handAngles(hour: 0, minute: 0).hour, 0)
        XCTAssertEqual(WorldClock.handAngles(hour: 3, minute: 0).hour, 90)
        XCTAssertEqual(WorldClock.handAngles(hour: 15, minute: 30).hour, 105)
        XCTAssertEqual(WorldClock.handAngles(hour: 15, minute: 30).minute, 180)
        XCTAssertEqual(WorldClock.handAngles(hour: 9, minute: 45).minute, 270)
    }
}

final class DayProgressWindowTests: XCTestCase {
    private let day = DayProgress(startHour: 9, endHour: 17, calendar: utc)

    func testWorkingHours() {
        XCTAssertFalse(day.isWorking(at: date(8, 59)))
        XCTAssertTrue(day.isWorking(at: date(9)))
        XCTAssertTrue(day.isWorking(at: date(16, 59)))
        XCTAssertFalse(day.isWorking(at: date(17)))
    }

    func testNextStartIsTodayBeforeTheDayAndTomorrowAfterIt() {
        XCTAssertEqual(day.nextStart(after: date(7)), date(9))
        XCTAssertEqual(day.nextStart(after: date(18)), date(day: 30, 9))
        XCTAssertEqual(day.nextStart(after: date(12)), date(day: 30, 9))
    }

    func testHourMarksCoverTheDay() {
        let hours = day.hourMarks(on: date(12))
        XCTAssertEqual(hours.map(\.hour), Array(9...17))
        XCTAssertEqual(hours.first?.fraction, 0)
        XCTAssertEqual(hours.last?.fraction, 1)
        XCTAssertEqual(hours[4].fraction, 0.5)
    }

    func testOneEventsMark() {
        XCTAssertEqual(day.mark(for: date(13)...date(14), on: date(12)), 0.5...0.625)
        XCTAssertNil(day.mark(for: date(7)...date(8), on: date(12)))
    }

    func testOverlappingEventsTakeSeparateLanes() {
        let lanes = DayProgress.lanes(for: [0.0...0.25, 0.1...0.3, 0.26...0.5, 0.2...0.28])
        XCTAssertEqual(lanes, [0, 1, 0, 2])
    }

    func testBackToBackEventsShareALane() {
        XCTAssertEqual(DayProgress.lanes(for: [0.0...0.25, 0.25...0.5]), [0, 0])
        XCTAssertEqual(DayProgress.lanes(for: []), [])
    }
}
