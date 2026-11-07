import XCTest

@testable import WispCore

final class RefreshRuleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let rule = RefreshRule(maxAge: 300)

    func testDueWhenNeverRefreshed() {
        XCTAssertTrue(rule.isDue(lastRefresh: nil, now: start))
    }

    func testNotDueWhileFresh() {
        XCTAssertFalse(rule.isDue(lastRefresh: start, now: start))
        XCTAssertFalse(rule.isDue(lastRefresh: start, now: start.addingTimeInterval(299)))
    }

    func testDueOnceOld() {
        XCTAssertTrue(rule.isDue(lastRefresh: start, now: start.addingTimeInterval(300)))
        XCTAssertTrue(rule.isDue(lastRefresh: start, now: start.addingTimeInterval(3600)))
    }

    func testDirtyForcesARefreshEvenWhenFresh() {
        XCTAssertTrue(rule.isDue(lastRefresh: start, now: start.addingTimeInterval(1), dirty: true))
    }

    func testClockMovingBackCountsAsDue() {
        // A clock set back would otherwise keep a stale read for as long as it moved.
        XCTAssertTrue(rule.isDue(lastRefresh: start, now: start.addingTimeInterval(-60)))
    }

    func testSharedRules() {
        XCTAssertEqual(RefreshRule.calendar.maxAge, 300)
        XCTAssertEqual(RefreshRule.shortcuts.maxAge, 300)
        XCTAssertEqual(RefreshRule.agentHooks.maxAge, 30)
        XCTAssertFalse(RefreshRule.agentHooks.isDue(lastRefresh: start, now: start.addingTimeInterval(29)))
        XCTAssertTrue(RefreshRule.agentHooks.isDue(lastRefresh: start, now: start.addingTimeInterval(30)))
    }
}
