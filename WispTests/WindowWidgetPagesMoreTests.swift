import XCTest

@testable import WispCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

private func date(day: Int = 29, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
}

final class CalendarWeekTests: XCTestCase {
    func testListsSevenDaysFromTodayIncludingEmptyOnes() {
        let week = CalendarDays.week([date(day: 31, 9)], date: { $0 }, now: date(10), calendar: utc)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map(\.label).prefix(3), ["Today", "Tomorrow", "Sat 31"])
        XCTAssertEqual(week.map(\.items.count), [0, 0, 1, 0, 0, 0, 0])
    }

    func testSortsEachDay() {
        let week = CalendarDays.week([date(15), date(9), date(12)], date: { $0 }, now: date(8), calendar: utc)
        XCTAssertEqual(week[0].items, [date(9), date(12), date(15)])
    }

    func testAnEventThatStartedBeforeTodayShowsToday() {
        let week = CalendarDays.week([date(day: 27, 0)], date: { $0 }, now: date(10), calendar: utc)
        XCTAssertEqual(week[0].items, [date(day: 27, 0)])
    }

    func testDropsItemsAfterTheLastDay() {
        let week = CalendarDays.week(
            [date(day: 29, 23), date(day: 30, 1)], date: { $0 }, now: date(10), days: 1, calendar: utc)
        XCTAssertEqual(week.count, 1)
        XCTAssertEqual(week[0].items, [date(day: 29, 23)])
    }

    func testNoDaysAskedForIsEmpty() {
        XCTAssertTrue(CalendarDays.week([date(10)], date: { $0 }, now: date(10), days: 0, calendar: utc).isEmpty)
    }
}

final class BatteryTextTests: XCTestCase {
    func testStatus() {
        XCTAssertEqual(BatteryText.status(BatteryState(percent: 50, isPluggedIn: true, isCharging: true)), "Charging")
        XCTAssertEqual(BatteryText.status(BatteryState(percent: 100, isPluggedIn: true, isCharging: false)), "On power")
        XCTAssertEqual(
            BatteryText.status(BatteryState(percent: 50, isPluggedIn: false, isCharging: false)), "On battery")
    }

    func testRemainingSaysWhichWay() {
        let charging = BatteryState(percent: 40, isPluggedIn: true, isCharging: true)
        let draining = BatteryState(percent: 40, isPluggedIn: false, isCharging: false)
        XCTAssertEqual(BatteryText.remaining(minutes: 80, state: charging), "1h 20m to full")
        XCTAssertEqual(BatteryText.remaining(minutes: 45, state: draining), "45m left")
        XCTAssertEqual(BatteryText.remaining(minutes: 120, state: draining), "2h 0m left")
    }

    func testRemainingIsNilWhenUnknown() {
        let state = BatteryState(percent: 40, isPluggedIn: false, isCharging: false)
        XCTAssertNil(BatteryText.remaining(minutes: nil, state: state))
        XCTAssertNil(BatteryText.remaining(minutes: 0, state: state))
    }

    func testPartsAreOrderedAndLabelled() {
        let buds = BluetoothDevice(
            name: "AirPods", address: "a", kind: "Headphones", battery: [.case: 90, .right: 60, .left: 55])
        XCTAssertEqual(BatteryText.parts(of: buds).map(\.label), ["Left", "Right", "Case"])
        XCTAssertEqual(BatteryText.parts(of: buds).map(\.level), [55, 60, 90])
        let mouse = BluetoothDevice(name: "Mouse", address: "b", kind: "Mouse", battery: [.main: 12])
        XCTAssertEqual(BatteryText.parts(of: mouse).map(\.label), ["Battery"])
        XCTAssertTrue(BatteryText.parts(of: mouse)[0].isLow)
        XCTAssertFalse(BatteryText.parts(of: mouse, lowLevel: 10)[0].isLow)
        XCTAssertTrue(BatteryText.parts(of: buds, lowLevel: 55)[0].isLow)
    }

    func testLowestLevel() {
        let buds = BluetoothDevice(name: "AirPods", address: "a", kind: "", battery: [.case: 90, .left: 15])
        XCTAssertEqual(BatteryText.lowestLevel(of: buds), 15)
        XCTAssertNil(BatteryText.lowestLevel(of: BluetoothDevice(name: "X", address: "c", kind: "", battery: [:])))
    }
}

final class SampleHistorySummaryTests: XCTestCase {
    func testAverageAndPeak() {
        var history = SampleHistory(capacity: 4)
        XCTAssertNil(history.average)
        XCTAssertNil(history.peak)
        [0.2, 0.4, 0.9, 0.5].forEach { history.append($0) }
        XCTAssertEqual(history.average ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(history.peak, 0.9)
    }

    func testSummaryFollowsTheWindow() {
        var history = SampleHistory(capacity: 2)
        [1, 0.2, 0.4].forEach { history.append($0) }
        XCTAssertEqual(history.peak, 0.4)
        XCTAssertEqual(history.average ?? 0, 0.3, accuracy: 0.0001)
    }
}

final class ShortcutSearchTests: XCTestCase {
    private let names = ["Resize Image", "Make GIF", "Café hours", "Send ETA"]

    func testEmptyQueryKeepsAll() {
        XCTAssertEqual(ShortcutList.matching(names, query: "  "), names)
    }

    func testMatchesEveryWordIgnoringCaseAndAccents() {
        XCTAssertEqual(ShortcutList.matching(names, query: "image"), ["Resize Image"])
        XCTAssertEqual(ShortcutList.matching(names, query: "cafe"), ["Café hours"])
        XCTAssertEqual(ShortcutList.matching(names, query: "make gif"), ["Make GIF"])
        XCTAssertEqual(ShortcutList.matching(names, query: "gif resize"), [])
    }
}

final class ScriptTranscriptTests: XCTestCase {
    func testKeepsInnerBlankLinesAndIndentation() {
        XCTAssertEqual(
            ScriptOutput.transcript(from: "\n\nfirst\n\n  indented  \nlast\n\n", limit: 10),
            ["first", "", "  indented", "last"])
    }

    func testStripsColoursAndStopsAtTheLimit() {
        XCTAssertEqual(ScriptOutput.transcript(from: "\u{1B}[31mone\u{1B}[0m\ntwo\nthree", limit: 2), ["one", "two"])
        XCTAssertEqual(ScriptOutput.transcript(from: "one", limit: 0), [])
    }

    func testCutsVeryLongLines() {
        let line = String(repeating: "x", count: ScriptOutput.maxTranscriptLineLength + 10)
        XCTAssertEqual(
            ScriptOutput.transcript(from: line, limit: 1).first?.count, ScriptOutput.maxTranscriptLineLength)
    }

    func testCarriageReturnsSplitLines() {
        XCTAssertEqual(ScriptOutput.transcript(from: "a\r\nb", limit: 5), ["a", "b"])
    }
}
