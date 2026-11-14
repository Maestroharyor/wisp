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
            Set(ActivitySlot.allCases.filter(\.canBeBubble)),
            [.media, .timer, .agent, .meeting, .external, .regionWatch])
    }

    func testCardsAndAlertsCanBeDismissedButOngoingActivitiesCant() {
        let dismissable: Set<ActivitySlot> = [
            .notification, .notice, .timerDone, .device, .battery, .focus, .meetingSoon, .tray, .downloadDone,
            .aiResult,
            .quickInput, .agentCallout,
        ]
        XCTAssertEqual(Set(ActivitySlot.allCases.filter(\.isDismissable)), dismissable)
    }

    func testAgentCalloutsSitBelowRequestsButOverNotifications() {
        XCTAssertLessThan(ActivitySlot.agentCallout.priority, ActivitySlot.agentApproval.priority)
        XCTAssertGreaterThan(ActivitySlot.agentCallout.priority, ActivitySlot.notification.priority)
    }

    func testShortAlertsShowDuringACall() {
        for alert in [ActivitySlot.battery, .device, .focus, .tray] {
            XCTAssertGreaterThan(alert.priority, ActivitySlot.meeting.priority, "\(alert)")
        }
    }

    func testOngoingActivitiesKeepTheirOrder() {
        XCTAssertGreaterThan(ActivitySlot.meeting.priority, ActivitySlot.timer.priority)
        XCTAssertGreaterThan(ActivitySlot.timer.priority, ActivitySlot.external.priority)
        XCTAssertGreaterThan(ActivitySlot.external.priority, ActivitySlot.agent.priority)
        XCTAssertGreaterThan(ActivitySlot.agent.priority, ActivitySlot.media.priority)
        XCTAssertGreaterThan(ActivitySlot.timer.priority, ActivitySlot.regionWatch.priority)
        XCTAssertGreaterThan(ActivitySlot.regionWatch.priority, ActivitySlot.agent.priority)
        // A watch the user set up in Wisp outranks a script's activity.
        XCTAssertGreaterThan(ActivitySlot.regionWatch.priority, ActivitySlot.external.priority)
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

final class AIResultSlotTests: XCTestCase {
    func testTheResultCardCanBeClosedAndShowsOverNoticesButUnderNotifications() {
        XCTAssertTrue(ActivitySlot.aiResult.isDismissable)
        XCTAssertFalse(ActivitySlot.aiResult.canBeBubble)
        XCTAssertGreaterThan(ActivitySlot.aiResult.priority, ActivitySlot.notice.priority)
        XCTAssertGreaterThan(ActivitySlot.aiResult.priority, ActivitySlot.downloadDone.priority)
        XCTAssertLessThan(ActivitySlot.aiResult.priority, ActivitySlot.notification.priority)
    }

    func testAJoinCardShowsOverTheResultCard() {
        XCTAssertGreaterThan(ActivitySlot.meetingSoon.priority, ActivitySlot.aiResult.priority)
    }
}

final class QuickInputSlotTests: XCTestCase {
    func testTheConfirmCardShowsOverNotificationsButUnderApprovals() {
        XCTAssertTrue(ActivitySlot.quickInput.isDismissable)
        XCTAssertFalse(ActivitySlot.quickInput.canBeBubble)
        XCTAssertGreaterThan(ActivitySlot.quickInput.priority, ActivitySlot.notification.priority)
        XCTAssertLessThan(ActivitySlot.quickInput.priority, ActivitySlot.agentApproval.priority)
    }
}
