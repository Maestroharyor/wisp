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

final class DisplayNameTests: XCTestCase {
    func testANamedDisplayKeepsItsName() {
        XCTAssertEqual(
            DisplayName.title(name: "LG UltraFine", builtIn: false, width: 2560, height: 1440), "LG UltraFine")
    }

    func testAnUnnamedDisplayIsNamedByKindAndSize() {
        XCTAssertEqual(
            DisplayName.title(name: "", builtIn: false, width: 1920, height: 1080), "External display (1920 × 1080)")
        XCTAssertEqual(DisplayName.title(name: "  ", builtIn: true, width: 1512, height: 982), "Built-in display")
    }
}
