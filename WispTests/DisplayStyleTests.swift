import XCTest

@testable import WispCore

final class DisplayStyleTests: XCTestCase {
    func testDefaultFollowsTheExternalSettings() {
        XCTAssertEqual(
            DisplayStyle.resolve(.automatic, hasNotch: true, showOnExternal: false, externalIsland: true), .notch)
        XCTAssertEqual(
            DisplayStyle.resolve(.automatic, hasNotch: false, showOnExternal: false, externalIsland: false), .hidden)
        XCTAssertEqual(
            DisplayStyle.resolve(.automatic, hasNotch: false, showOnExternal: true, externalIsland: true), .island)
        XCTAssertEqual(
            DisplayStyle.resolve(.automatic, hasNotch: false, showOnExternal: true, externalIsland: false), .notch)
    }

    func testAPerDisplayChoiceWins() {
        XCTAssertEqual(
            DisplayStyle.resolve(.hidden, hasNotch: true, showOnExternal: true, externalIsland: false), .hidden)
        XCTAssertEqual(
            DisplayStyle.resolve(.island, hasNotch: false, showOnExternal: false, externalIsland: false), .island)
        XCTAssertEqual(
            DisplayStyle.resolve(.notch, hasNotch: false, showOnExternal: true, externalIsland: true), .notch)
    }
}
