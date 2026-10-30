import XCTest

@testable import WispCore

final class SwipeDetectorTests: XCTestCase {
    func testSmallMovementsAreNotSwipes() {
        var detector = SwipeDetector()
        XCTAssertNil(detector.add(dx: 3, dy: 2))
        XCTAssertNil(detector.add(dx: 4, dy: 1))
    }

    func testTwoFingersDownIsASwipeDown() {
        var detector = SwipeDetector()
        XCTAssertNil(detector.add(dx: 0, dy: -20))
        XCTAssertEqual(detector.add(dx: 2, dy: -30), .down)
    }

    func testSidewaysSwipes() {
        var left = SwipeDetector()
        XCTAssertEqual(left.add(dx: -60, dy: 5), .left)
        var right = SwipeDetector()
        XCTAssertEqual(right.add(dx: 60, dy: -5), .right)
    }

    func testOneGestureFiresOnce() {
        var detector = SwipeDetector()
        XCTAssertEqual(detector.add(dx: 0, dy: 60), .up)
        XCTAssertNil(detector.add(dx: 0, dy: 60))
        detector.reset()
        XCTAssertEqual(detector.add(dx: 0, dy: 60), .up)
    }

    func testDiagonalNeedsAClearDirection() {
        var detector = SwipeDetector()
        XCTAssertNil(detector.add(dx: 45, dy: 45))
    }
}
