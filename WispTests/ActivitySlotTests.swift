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
        let dismissable: Set<ActivitySlot> = [.notification, .notice, .device, .battery, .focus, .meetingSoon, .tray]
        XCTAssertEqual(Set(ActivitySlot.allCases.filter(\.isDismissable)), dismissable)
    }
}
