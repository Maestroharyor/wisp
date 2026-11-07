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
            Set(ActivitySlot.allCases.filter(\.canBeBubble)), [.media, .timer, .agent, .meeting, .external])
    }

    func testCardsAndAlertsCanBeDismissedButOngoingActivitiesCant() {
        let dismissable: Set<ActivitySlot> = [
            .notification, .notice, .timerDone, .device, .battery, .focus, .meetingSoon, .tray,
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
        XCTAssertGreaterThan(ActivitySlot.timer.priority, ActivitySlot.external.priority)
        XCTAssertGreaterThan(ActivitySlot.external.priority, ActivitySlot.agent.priority)
        XCTAssertGreaterThan(ActivitySlot.agent.priority, ActivitySlot.media.priority)
    }
}
