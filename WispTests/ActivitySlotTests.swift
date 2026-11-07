import XCTest

@testable import WispCore

final class ActivitySlotTests: XCTestCase {
    func testPrioritiesAreDistinct() {
        let priorities = ActivitySlot.allCases.map(\.priority)
        XCTAssertEqual(Set(priorities).count, priorities.count)
    }

    func testHUDsOutrankEverything() {
        let others = ActivitySlot.allCases.filter { $0 != .level }
        XCTAssertTrue(others.allSatisfy { $0.priority < ActivitySlot.level.priority })
    }

    func testOnlyStickyGlyphSourcesBecomeBubbles() {
        XCTAssertEqual(
            Set(ActivitySlot.allCases.filter(\.canBeBubble)), [.media, .timer, .agent, .meeting])
    }

    func testCardsAndAlertsCanBeDismissedButOngoingActivitiesCant() {
        let dismissable: Set<ActivitySlot> = [
            .notification, .notice, .timerDone, .device, .battery, .focus, .meetingSoon, .tray, .downloadDone,
        ]
        XCTAssertEqual(Set(ActivitySlot.allCases.filter(\.isDismissable)), dismissable)
    }

    func testShortAlertsShowDuringACall() {
        for alert in [ActivitySlot.battery, .device, .focus, .tray] {
            XCTAssertGreaterThan(alert.priority, ActivitySlot.meeting.priority, "\(alert)")
        }
    }

    func testOngoingActivitiesKeepTheirOrder() {
        XCTAssertGreaterThan(ActivitySlot.meeting.priority, ActivitySlot.timer.priority)
        XCTAssertGreaterThan(ActivitySlot.timer.priority, ActivitySlot.agent.priority)
        XCTAssertGreaterThan(ActivitySlot.agent.priority, ActivitySlot.media.priority)
    }
}

final class DownloadSlotTests: XCTestCase {
    func testADownloadInProgressIsOngoingAndSitsUnderAlerts() {
        XCTAssertFalse(ActivitySlot.download.isDismissable)
        XCTAssertGreaterThan(ActivitySlot.download.priority, ActivitySlot.timer.priority)
        XCTAssertLessThan(ActivitySlot.download.priority, ActivitySlot.meeting.priority)
    }

    func testTheFinishedCardCanBeClosedAndShowsOverOngoingActivities() {
        XCTAssertTrue(ActivitySlot.downloadDone.isDismissable)
        XCTAssertGreaterThan(ActivitySlot.downloadDone.priority, ActivitySlot.tray.priority)
        XCTAssertLessThan(ActivitySlot.downloadDone.priority, ActivitySlot.notification.priority)
    }
}
