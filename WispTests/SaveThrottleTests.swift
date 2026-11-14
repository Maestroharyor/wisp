import XCTest

@testable import WispCore

final class SaveThrottleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testNothingToSaveUntilSomethingChanges() {
        let throttle = SaveThrottle(interval: 5)
        XCTAssertFalse(throttle.isPending)
        XCTAssertNil(throttle.wait(now: start))
    }

    func testTheFirstChangeSavesRightAway() {
        var throttle = SaveThrottle(interval: 5)
        throttle.markChanged()
        XCTAssertTrue(throttle.isPending)
        XCTAssertEqual(throttle.wait(now: start), 0)
    }

    func testAChangeSoonAfterASaveWaitsOutTheInterval() {
        var throttle = SaveThrottle(interval: 5)
        throttle.markChanged()
        throttle.saved(at: start)
        XCTAssertFalse(throttle.isPending)
        XCTAssertNil(throttle.wait(now: start.addingTimeInterval(1)))
        throttle.markChanged()
        XCTAssertEqual(throttle.wait(now: start.addingTimeInterval(1)), 4)
        XCTAssertEqual(throttle.wait(now: start.addingTimeInterval(5)), 0)
        XCTAssertEqual(throttle.wait(now: start.addingTimeInterval(60)), 0)
    }

    func testClockMovingBackSavesRightAway() {
        // Otherwise a clock set back an hour would hold the save for that hour.
        var throttle = SaveThrottle(interval: 5)
        throttle.saved(at: start)
        throttle.markChanged()
        XCTAssertEqual(throttle.wait(now: start.addingTimeInterval(-3600)), 0)
    }

    func testSavingClearsThePendingChange() {
        var throttle = SaveThrottle(interval: 5)
        throttle.markChanged()
        throttle.markChanged()
        throttle.saved(at: start)
        XCTAssertFalse(throttle.isPending)
    }
}
