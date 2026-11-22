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
        XCTAssertEqual(read.centre, .clear)
    }

    func testTheCentreIsClearUnlessChosen() throws {
        XCTAssertEqual(RingLook.standard.centre, .clear)
        var look = RingLook()
        look.centre = .tinted
        let data = try JSONEncoder().encode(look)
        XCTAssertEqual(try JSONDecoder().decode(RingLook.self, from: data).centre, .tinted)
        let unknown = try JSONDecoder().decode(RingLook.self, from: Data(#"{"centre": "neon"}"#.utf8))
        XCTAssertEqual(unknown.centre, .clear)
    }

    func testTheRingHasItsGlassBandUnlessChosen() throws {
        XCTAssertEqual(RingLook.standard.backdrop, .band)
        var look = RingLook()
        look.backdrop = .orbit
        let data = try JSONEncoder().encode(look)
        XCTAssertEqual(try JSONDecoder().decode(RingLook.self, from: data).backdrop, .orbit)
        let old = try JSONDecoder().decode(RingLook.self, from: Data(#"{"centre": "frosted"}"#.utf8))
        XCTAssertEqual(old.backdrop, .band)
        XCTAssertEqual(old.centre, .frosted)
    }

    func testTheBackgroundColourIsOptionalAndKeptInRange() throws {
        XCTAssertNil(RingLook.standard.colour)
        var look = RingLook()
        look.colour = RGB(red: 0.1, green: 0.2, blue: 0.3)
        look.colourAmount = 4
        XCTAssertEqual(look.clamped().colourAmount, 1)
        XCTAssertEqual(look.colourOpacity, 0.9, accuracy: 0.0001)
        look.colourAmount = 0
        XCTAssertEqual(look.colourOpacity, 0.15, accuracy: 0.0001)
        let data = try JSONEncoder().encode(look)
        XCTAssertEqual(try JSONDecoder().decode(RingLook.self, from: data).colour, look.colour)
        XCTAssertNil(try JSONDecoder().decode(RingLook.self, from: Data(#"{"colour": "pink"}"#.utf8)).colour)
    }
}
