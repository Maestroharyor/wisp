import XCTest

@testable import WispCore

final class TextStyleSizeTests: XCTestCase {
    func testDefaultScaleKeepsMacSizes() {
        XCTAssertEqual(TextStyleSize.body.points(scale: 1), 13)
        XCTAssertEqual(TextStyleSize.largeTitle.points(scale: 1), 26)
        XCTAssertEqual(TextStyleSize.caption2.points(scale: 1), 10)
    }

    func testScaleRoundsToHalfPoints() {
        XCTAssertEqual(TextStyleSize.body.points(scale: 1.25), 16.5)
        XCTAssertEqual(TextStyleSize.body.points(scale: 1.12), 14.5)
        XCTAssertEqual(TextStyleSize.caption.points(scale: 1.12), 11)
    }

    func testHeadlineIsBold() {
        XCTAssertTrue(TextStyleSize.headline.isBold)
        XCTAssertFalse(TextStyleSize.body.isBold)
    }

    func testScaledSizeRoundsAnyPointSize() {
        XCTAssertEqual(TextStyleSize.scaled(60, by: 1), 60)
        XCTAssertEqual(TextStyleSize.scaled(60, by: 1.12), 67)
    }
}
