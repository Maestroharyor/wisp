import XCTest

@testable import WispCore

final class QuietHoursTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        let parts = DateComponents(year: 2026, month: 11, day: 14, hour: hour, minute: minute)
        return calendar.date(from: parts) ?? .distantPast
    }

    // MARK: Schedule

    func testOffByDefaultWithEveryGroupChosen() {
        let hours = QuietHours()
        XCTAssertFalse(hours.on)
        XCTAssertEqual(hours.groups, Set(AgentAlertGroup.allCases))
        XCTAssertFalse(hours.isQuiet(.done, at: date(hour: 23), calendar: calendar))
    }

    func testScheduleWithinADay() {
        let hours = QuietHours(on: true, start: 12 * 60, end: 14 * 60)
        XCTAssertFalse(hours.covers(minuteOfDay: 11 * 60 + 59))
        XCTAssertTrue(hours.covers(minuteOfDay: 12 * 60))
        XCTAssertTrue(hours.covers(minuteOfDay: 13 * 60 + 59))
        XCTAssertFalse(hours.covers(minuteOfDay: 14 * 60))
    }

    func testScheduleCrossingMidnight() {
        let hours = QuietHours(on: true, start: 22 * 60, end: 7 * 60)
        XCTAssertTrue(hours.isQuiet(.done, at: date(hour: 22), calendar: calendar))
        XCTAssertTrue(hours.isQuiet(.done, at: date(hour: 23, minute: 59), calendar: calendar))
        XCTAssertTrue(hours.isQuiet(.done, at: date(hour: 0), calendar: calendar))
        XCTAssertTrue(hours.isQuiet(.done, at: date(hour: 6, minute: 59), calendar: calendar))
        XCTAssertFalse(hours.isQuiet(.done, at: date(hour: 7), calendar: calendar))
        XCTAssertFalse(hours.isQuiet(.done, at: date(hour: 21, minute: 59), calendar: calendar))
    }

    func testTheSameStartAndEndIsNeverQuiet() {
        let hours = QuietHours(on: true, start: 9 * 60, end: 9 * 60)
        XCTAssertFalse(hours.covers(minuteOfDay: 9 * 60))
        XCTAssertFalse(hours.covers(minuteOfDay: 3 * 60))
    }

    func testOnlyChosenGroupsGoQuiet() {
        let hours = QuietHours(on: true, start: 0, end: 24 * 60 - 1, groups: [.done])
        let noon = date(hour: 12)
        XCTAssertTrue(hours.isQuiet(.done, at: noon, calendar: calendar))
        XCTAssertFalse(hours.isQuiet(.needsYou, at: noon, calendar: calendar))
        XCTAssertFalse(hours.isQuiet(.limits, at: noon, calendar: calendar))
    }

    func testOutOfRangeTimesAreClamped() {
        let hours = QuietHours(on: true, start: -40, end: 5000)
        XCTAssertEqual(hours.start, 0)
        XCTAssertEqual(hours.end, 24 * 60 - 1)
    }

    func testTimesSplitIntoHourAndMinute() {
        var hours = QuietHours(on: true, start: 22 * 60 + 30, end: 7 * 60)
        XCTAssertEqual(QuietHours.hourAndMinute(hours.start).hour, 22)
        XCTAssertEqual(QuietHours.hourAndMinute(hours.start).minute, 30)
        hours.start = QuietHours.minuteOfDay(hour: 6, minute: 15)
        XCTAssertEqual(hours.start, 6 * 60 + 15)
    }

    // MARK: Mute

    func testMuteSilencesEveryGroupUntilItEnds() {
        let hours = QuietHours()
        let noon = date(hour: 12)
        let until = noon.addingTimeInterval(3600)
        for group in AgentAlertGroup.allCases {
            XCTAssertTrue(
                AlertQuiet.isQuiet(group, hours: hours, mutedUntil: until, now: noon, calendar: calendar), "\(group)")
            XCTAssertFalse(
                AlertQuiet.isQuiet(group, hours: hours, mutedUntil: until, now: until, calendar: calendar), "\(group)")
        }
        XCTAssertFalse(AlertQuiet.isQuiet(.done, hours: hours, mutedUntil: nil, now: noon, calendar: calendar))
    }

    func testQuietHoursApplyWithoutAMute() {
        let hours = QuietHours(on: true, start: 22 * 60, end: 7 * 60, groups: [.needsYou])
        XCTAssertTrue(
            AlertQuiet.isQuiet(.needsYou, hours: hours, mutedUntil: nil, now: date(hour: 1), calendar: calendar))
        XCTAssertFalse(
            AlertQuiet.isQuiet(.done, hours: hours, mutedUntil: nil, now: date(hour: 1), calendar: calendar))
    }

    func testAMuteThatEndedIsDropped() {
        let noon = date(hour: 12)
        XCTAssertNil(AlertQuiet.activeMute(noon.addingTimeInterval(-1), now: noon))
        XCTAssertNil(AlertQuiet.activeMute(nil, now: noon))
        XCTAssertEqual(AlertQuiet.activeMute(noon.addingTimeInterval(60), now: noon), noon.addingTimeInterval(60))
    }

    // MARK: Groups

    func testEverySoundBelongsToAGroup() {
        XCTAssertEqual(AgentSoundEvent.needsApproval.group, .needsYou)
        XCTAssertEqual(AgentSoundEvent.question.group, .needsYou)
        XCTAssertEqual(AgentSoundEvent.finished.group, .done)
        XCTAssertEqual(AgentSoundEvent.failed.group, .done)
        XCTAssertEqual(AgentSoundEvent.contextWarning.group, .limits)
        XCTAssertEqual(AgentSoundEvent.contextCritical.group, .limits)
        XCTAssertEqual(AgentSoundEvent.spendCap.group, .limits)
        XCTAssertEqual(AgentSoundEvent.limitWarning.group, .limits)
        XCTAssertEqual(AgentSoundEvent.limitReached.group, .limits)
        XCTAssertEqual(AgentSoundEvent.limitReset.group, .limits)
    }

    func testEveryPushKindBelongsToAGroup() {
        XCTAssertEqual(PushKind.approval.group, .needsYou)
        XCTAssertEqual(PushKind.needsYou.group, .needsYou)
        XCTAssertEqual(PushKind.done.group, .done)
        XCTAssertEqual(PushKind.cloud.group, .done)
        XCTAssertEqual(PushKind.limit.group, .limits)
        XCTAssertEqual(PushKind.budget.group, .limits)
    }

    func testRoundTripsAndKeepsDefaultsForMissingKeys() throws {
        let hours = QuietHours(on: true, start: 23 * 60, end: 6 * 60 + 30, groups: [.done, .limits])
        let data = try JSONEncoder().encode(hours)
        XCTAssertEqual(try JSONDecoder().decode(QuietHours.self, from: data), hours)

        let partial = try JSONDecoder().decode(QuietHours.self, from: Data(#"{"on":true,"groups":["bogus"]}"#.utf8))
        XCTAssertTrue(partial.on)
        XCTAssertEqual(partial.start, QuietHours().start)
        XCTAssertEqual(partial.end, QuietHours().end)
        XCTAssertEqual(partial.groups, [])
    }

    func testTitles() {
        XCTAssertEqual(AgentAlertGroup.needsYou.title, "Needs you")
        XCTAssertEqual(AgentAlertGroup.done.title, "Done")
        XCTAssertEqual(AgentAlertGroup.limits.title, "Limits")
    }
}
