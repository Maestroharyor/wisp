import XCTest

@testable import WispCore

final class DurationTextTests: XCTestCase {
    func testParsesUnits() {
        XCTAssertEqual(DurationText.seconds(from: "2h15m"), 8100)
        XCTAssertEqual(DurationText.seconds(from: "90s"), 90)
        XCTAssertEqual(DurationText.seconds(from: "1h 30m 10s"), 5410)
        XCTAssertEqual(DurationText.seconds(from: "45M"), 2700)
    }

    func testPlainNumbersAreMinutes() {
        XCTAssertEqual(DurationText.seconds(from: "25"), 1500)
        XCTAssertEqual(DurationText.seconds(from: " 5 "), 300)
    }

    func testRejectsNonsense() {
        XCTAssertNil(DurationText.seconds(from: ""))
        XCTAssertNil(DurationText.seconds(from: "soon"))
        XCTAssertNil(DurationText.seconds(from: "5x"))
        XCTAssertNil(DurationText.seconds(from: "0"))
        XCTAssertNil(DurationText.seconds(from: "h"))
    }

    func testFormatsForEditing() {
        XCTAssertEqual(DurationText.text(for: 8100), "2h 15m")
        XCTAssertEqual(DurationText.text(for: 300), "5m")
        XCTAssertEqual(DurationText.text(for: 3600), "1h")
        XCTAssertEqual(DurationText.text(for: 90), "1m 30s")
    }
}
