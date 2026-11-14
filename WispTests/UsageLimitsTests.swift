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
        let alerts = watch.record([reading(85, resetsIn: 8 * 3600)], at: start + 60)
        XCTAssertEqual(alerts.map(\.kind), [.reset, .level], "the old window passed 80%, so its reset is said too")
        XCTAssertEqual(alerts.last?.level, 80)
    }

    func testAStaleLowerReadingDoesntStartTheWindowOver() {
        // Two sessions report the same account; one's figure can lag behind.
        var watch = LimitWatch()
        _ = watch.record([reading(82)], at: start)
        XCTAssertEqual(watch.record([reading(79)], at: start + 30), [])
        XCTAssertEqual(watch.record([reading(83)], at: start + 60), [])
    }

    func testWithoutAResetTimeAFallMeansANewWindow() {
        var watch = LimitWatch()
        let open = { (percent: Double) in UsageReading(window: .sevenDay, percent: percent, resets: nil) }
        _ = watch.record([open(85)], at: start)
        _ = watch.record([open(3)], at: start + 60)
        XCTAssertEqual(watch.record([open(81)], at: start + 120).map(\.level), [80])
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
            LimitWatch.clock(start + 3600, locale: posix, timeZone: utc).replacingOccurrences(
                of: "\u{202F}", with: " "),
            "9:00 AM", "newer ICU puts a narrow space before AM, older a plain one")
    }

    // MARK: Alert level, used up and reset

    func testTheAlertLevelCanBeChosen() {
        var watch = LimitWatch(threshold: 60)
        XCTAssertEqual(watch.record([reading(59)], at: start), [])
        XCTAssertEqual(watch.record([reading(61)], at: start + 60).map(\.level), [60])
        XCTAssertEqual(watch.record([reading(81)], at: start + 120), [], "80 is no longer a level")
        XCTAssertEqual(watch.record([reading(96)], at: start + 180).map(\.level), [95])
    }

    func testTheAlertLevelStaysInRange() {
        XCTAssertEqual(LimitWatch(threshold: 10).threshold, 50)
        var watch = LimitWatch()
        watch.threshold = 99
        XCTAssertEqual(watch.threshold, 95)
        XCTAssertEqual(watch.levels, [95, 100])
    }

    func testUsedUpIsItsOwnAlert() {
        var watch = LimitWatch()
        _ = watch.record([reading(96)], at: start)
        let alerts = watch.record([reading(100)], at: start + 60)
        XCTAssertEqual(alerts.map(\.kind), [.exhausted])
        XCTAssertEqual(alerts.first?.text, "5 h limit used up")
        XCTAssertEqual(alerts.first?.sound, .limitReached)
        XCTAssertEqual(watch.record([reading(100)], at: start + 120), [])
    }

    func testAJumpToUsedUpGivesOnlyThatAlert() {
        var watch = LimitWatch()
        XCTAssertEqual(watch.record([reading(100)], at: start).map(\.kind), [.exhausted])
    }

    func testAResetIsAnnouncedFromTheNextWindowsReading() {
        var watch = LimitWatch()
        _ = watch.record([reading(85)], at: start)
        let alerts = watch.record([reading(2, resetsIn: 9 * 3600)], at: start + 5 * 3600)
        XCTAssertEqual(alerts.map(\.kind), [.reset])
        XCTAssertEqual(alerts.first?.text, "Your 5 h limit reset")
        XCTAssertEqual(alerts.first?.sound, .limitReset)
    }

    func testAResetIsAnnouncedFromTheClockOnce() {
        var watch = LimitWatch()
        _ = watch.record([reading(85, resetsIn: 3600)], at: start)
        XCTAssertEqual(watch.nextReset, start + 3600)
        XCTAssertEqual(watch.resetsDue(at: start + 1800), [])
        XCTAssertEqual(watch.resetsDue(at: start + 3600).map(\.window), [.fiveHour])
        XCTAssertNil(watch.nextReset)
        XCTAssertEqual(watch.resetsDue(at: start + 7200), [])
        // The new window's first reading doesn't say it again.
        XCTAssertEqual(watch.record([reading(1, resetsIn: 6 * 3600)], at: start + 7200), [])
    }

    func testAWindowThatNeverReachedTheAlertLevelResetsQuietly() {
        var watch = LimitWatch()
        _ = watch.record([reading(40, resetsIn: 3600)], at: start)
        XCTAssertNil(watch.nextReset)
        XCTAssertEqual(watch.resetsDue(at: start + 3600), [])
        XCTAssertEqual(watch.record([reading(1, resetsIn: 6 * 3600)], at: start + 3600), [])
    }

    func testAnOldWindowsReadingIsIgnored() {
        var watch = LimitWatch()
        _ = watch.record([reading(85)], at: start)
        _ = watch.record([reading(3, resetsIn: 9 * 3600)], at: start + 60)
        // Another session's snapshot from before the reset.
        XCTAssertEqual(watch.record([reading(90)], at: start + 120), [])
        XCTAssertEqual(watch.record([reading(10, resetsIn: 9 * 3600)], at: start + 180), [])
    }

    func testAResetTimeThatDriftsASecondIsTheSameWindow() {
        var watch = LimitWatch()
        _ = watch.record([reading(85)], at: start)
        XCTAssertEqual(watch.record([reading(86, resetsIn: 4 * 3600 + 2)], at: start + 60), [])
    }

    func testASnapshotWithoutTheResetTimeIsTheSameWindow() {
        var watch = LimitWatch()
        _ = watch.record([reading(85)], at: start)
        let bare = UsageReading(window: .fiveHour, percent: 86, resets: nil)
        XCTAssertEqual(watch.record([bare], at: start + 60), [], "no reset said for a dropped field")
        XCTAssertEqual(watch.record([reading(87)], at: start + 120), [])
        XCTAssertEqual(watch.nextReset, start + 4 * 3600)
    }

    func testOtherAgentsResetsNameTheAgent() {
        let alert = LimitAlert(window: .sevenDay, level: 0, percent: 0, resets: nil, source: .codex, kind: .reset)
        XCTAssertEqual(alert.text, "Your Codex weekly limit reset")
    }

    func testTheBarsFollowTheAlertLevel() {
        XCTAssertEqual(LimitWatch.level(percent: 79, threshold: 80), .normal)
        XCTAssertEqual(LimitWatch.level(percent: 80, threshold: 80), .warning)
        XCTAssertEqual(LimitWatch.level(percent: 95, threshold: 80), .critical)
        // A lower alert level turns the bar amber sooner.
        XCTAssertEqual(LimitWatch.level(percent: 60, threshold: 60), .warning)
        XCTAssertEqual(LimitWatch.level(percent: 59, threshold: 60), .normal)
        // At 95 the alert level is the critical one, so it goes straight to red.
        XCTAssertEqual(LimitWatch.level(percent: 90, threshold: 95), .normal)
        XCTAssertEqual(LimitWatch.level(percent: 95, threshold: 95), .critical)
        // A level out of range is clamped as the setting is.
        XCTAssertEqual(LimitWatch.level(percent: 45, threshold: 10), .normal)
        XCTAssertEqual(LimitWatch.level(percent: 50, threshold: 10), .warning)
    }
}
