import XCTest

@testable import WispCore

final class UsageLimitsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let posix = Locale(identifier: "en_US_POSIX")

    private func reading(_ percent: Double, resetsIn: TimeInterval = 4 * 3600, _ window: LimitWindow = .fiveHour)
        -> UsageReading
    {
        UsageReading(window: window, percent: percent, resets: start.addingTimeInterval(resetsIn))
    }

    func testReadsBothWindowsAndTheirResets() {
        let snapshot = StatusLineSnapshot.decode(
            Data(
                #"{"session_id":"s","rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1800003600},"seven_day":{"used_percentage":7}}}"#
                    .utf8))
        XCTAssertEqual(
            UsageLimits.readings(snapshot.extras),
            [
                UsageReading(window: .fiveHour, percent: 42, resets: Date(timeIntervalSince1970: 1_800_003_600)),
                UsageReading(window: .sevenDay, percent: 7, resets: nil),
            ])
    }

    func testAlertsOnceAtEachLevel() {
        var watch = LimitWatch()
        XCTAssertEqual(watch.record([reading(70)], at: start), [])
        XCTAssertEqual(watch.record([reading(81)], at: start + 60).map(\.level), [80])
        XCTAssertEqual(watch.record([reading(85)], at: start + 120), [])
        XCTAssertEqual(watch.record([reading(96)], at: start + 180).map(\.level), [95])
        XCTAssertEqual(watch.record([reading(99)], at: start + 240), [])
    }

    func testAJumpPastBothLevelsGivesOneAlert() {
        var watch = LimitWatch()
        XCTAssertEqual(watch.record([reading(97)], at: start).map(\.level), [95])
    }

    func testANewWindowAlertsAgain() {
        var watch = LimitWatch()
        _ = watch.record([reading(85)], at: start)
        XCTAssertEqual(watch.record([reading(85, resetsIn: 8 * 3600)], at: start + 60).map(\.level), [80])
    }

    func testWindowsAreWatchedSeparately() {
        var watch = LimitWatch()
        let fired = watch.record([reading(82), reading(83, .sevenDay)], at: start)
        XCTAssertEqual(fired.map(\.window), [.fiveHour, .sevenDay])
    }

    func testTheForecastFollowsTheBurnRate() throws {
        var watch = LimitWatch()
        _ = watch.record([reading(40)], at: start)
        _ = watch.record([reading(50)], at: start + 1800)
        // 10 points in 30 minutes: the other 50 take two and a half hours.
        let full = try XCTUnwrap(watch.forecast(.fiveHour))
        XCTAssertEqual(full.timeIntervalSince(start + 1800), 9000, accuracy: 1)
    }

    func testNoForecastWhenTheWindowResetsFirstOrUsageIsFlat() {
        var watch = LimitWatch()
        _ = watch.record([reading(10, resetsIn: 3600)], at: start)
        _ = watch.record([reading(12, resetsIn: 3600)], at: start + 900)
        XCTAssertNil(watch.forecast(.fiveHour), "at this rate it resets long before it fills")
        var flat = LimitWatch()
        _ = flat.record([reading(30)], at: start)
        _ = flat.record([reading(30)], at: start + 900)
        XCTAssertNil(flat.forecast(.fiveHour))
    }

    func testNoForecastFromTooShortAStretch() {
        var watch = LimitWatch()
        _ = watch.record([reading(40)], at: start)
        _ = watch.record([reading(45)], at: start + 60)
        XCTAssertNil(watch.forecast(.fiveHour))
    }

    func testTheAlertReadsPlainly() {
        let alert = LimitAlert(window: .fiveHour, level: 80, percent: 82.4, resets: start + 3600)
        XCTAssertEqual(alert.text, "5 h limit 82%")
        let weekly = LimitAlert(window: .sevenDay, level: 95, percent: 95, resets: nil)
        XCTAssertEqual(weekly.text, "Weekly limit 95%")
        XCTAssertEqual(
            LimitWatch.clock(start + 3600, locale: posix, timeZone: utc), "9:00\u{202F}AM",
            "ICU puts a narrow space before AM")
    }
}
