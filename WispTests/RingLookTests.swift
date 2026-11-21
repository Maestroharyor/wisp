import XCTest

@testable import WispCore

final class RingLookTests: XCTestCase {
    func testTheStandardRingIsClearAndFullSize() {
        XCTAssertEqual(RingLook.standard.glass, .clear)
        XCTAssertEqual(RingLook.standard.size, 1)
        XCTAssertEqual(RingLook.standard.tintFactor, 1)
    }

    func testSizeAndTintStayInRange() {
        var look = RingLook()
        look.size = 3
        look.tint = -1
        XCTAssertEqual(look.clamped().size, RingLook.sizeRange.upperBound)
        XCTAssertEqual(look.clamped().tint, 0)
    }

    func testAScaledRingHitTestsWhereItsIconsAreDrawn() {
        var look = RingLook()
        look.size = 1.25
        let centre = CGPoint(x: 100, y: 100)
        let point = look.unscaled(CGPoint(x: 225, y: 100), around: centre)
        XCTAssertEqual(point.x, 200, accuracy: 0.001)
        XCTAssertEqual(point.y, 100, accuracy: 0.001)
    }

    func testOldSettingsReadWithDefaults() throws {
        let read = try JSONDecoder().decode(RingLook.self, from: Data(#"{"size": 1.1}"#.utf8))
        XCTAssertEqual(read.size, 1.1, accuracy: 0.0001)
        XCTAssertEqual(read.glass, .clear)
        XCTAssertEqual(read.tint, 0.5)
    }
}
