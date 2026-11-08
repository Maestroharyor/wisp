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

    func testAMacWithASystemIslandGetsAFloatingIsland() {
        XCTAssertEqual(
            DisplayStyle.resolve(
                .automatic, hasNotch: true, showOnExternal: false, externalIsland: false, systemIsland: true),
            .island)
        XCTAssertEqual(
            DisplayStyle.resolve(
                .hidden, hasNotch: true, showOnExternal: false, externalIsland: false, systemIsland: true),
            .hidden)
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

final class NotchlessDisplayChoiceTests: XCTestCase {
    func testEveryStoredCombinationReadsAsOneChoice() {
        XCTAssertEqual(NotchlessDisplayChoice(showOnExternal: true, externalIsland: false), .notch)
        XCTAssertEqual(NotchlessDisplayChoice(showOnExternal: true, externalIsland: true), .island)
        XCTAssertEqual(NotchlessDisplayChoice(showOnExternal: false, externalIsland: false), .hidden)
        XCTAssertEqual(NotchlessDisplayChoice(showOnExternal: false, externalIsland: true), .hidden)
    }

    func testChoosingWritesTheStoredSettings() {
        for current in [false, true] {
            XCTAssertTrue(NotchlessDisplayChoice.notch.stored(externalIsland: current) == (true, false))
            XCTAssertTrue(NotchlessDisplayChoice.island.stored(externalIsland: current) == (true, true))
        }
    }

    func testDontShowKeepsTheStyleForLater() {
        XCTAssertTrue(NotchlessDisplayChoice.hidden.stored(externalIsland: true) == (false, true))
        XCTAssertTrue(NotchlessDisplayChoice.hidden.stored(externalIsland: false) == (false, false))
    }

    func testStoringAChoiceReadsBackAsThatChoice() {
        for current in [false, true] {
            for choice in NotchlessDisplayChoice.allCases {
                let stored = choice.stored(externalIsland: current)
                XCTAssertEqual(
                    NotchlessDisplayChoice(
                        showOnExternal: stored.showOnExternal, externalIsland: stored.externalIsland),
                    choice)
            }
        }
    }

    func testResolvedStyleIsUnchangedByTheMergedPicker() {
        // The picker writes the same two settings the resolver has always read.
        for choice in NotchlessDisplayChoice.allCases {
            let stored = choice.stored(externalIsland: false)
            let style = DisplayStyle.resolve(
                .automatic, hasNotch: false, showOnExternal: stored.showOnExternal,
                externalIsland: stored.externalIsland)
            XCTAssertEqual(style.rawValue, choice.rawValue)
        }
    }
}
