import XCTest

@testable import WispCore

final class AdvancedDisclosureTests: XCTestCase {
    func testClosedByDefault() {
        let state = AdvancedDisclosureState()
        XCTAssertFalse(state.isExpanded(query: ""))
        XCTAssertFalse(state.isExpanded(query: "   "))
    }

    func testOpensWhileSearchHasText() {
        let state = AdvancedDisclosureState()
        XCTAssertTrue(state.isExpanded(query: "volume"))
        XCTAssertTrue(state.isExpanded(query: " rows "))
    }

    func testClosesAgainWhenSearchClears() {
        let state = AdvancedDisclosureState()
        XCTAssertTrue(state.isExpanded(query: "glow"))
        XCTAssertFalse(state.isExpanded(query: ""))
    }

    func testOpeningByHandSurvivesASearch() {
        var state = AdvancedDisclosureState()
        state.setExpanded(true, query: "")
        XCTAssertTrue(state.isExpanded(query: ""))
        XCTAssertTrue(state.isExpanded(query: "glow"))
        XCTAssertTrue(state.isExpanded(query: ""))
    }

    func testClosingDuringASearchLastsUntilTheSearchChanges() {
        var state = AdvancedDisclosureState()
        state.setExpanded(false, query: "glow")
        XCTAssertFalse(state.isExpanded(query: "glow"))
        XCTAssertFalse(state.isExpanded(query: " GLOW "))
        XCTAssertTrue(state.isExpanded(query: "glow reach"))
    }

    func testClosingDuringASearchDoesNotChangeTheChoiceOutsideIt() {
        var state = AdvancedDisclosureState()
        state.setExpanded(true, query: "")
        state.setExpanded(false, query: "glow")
        XCTAssertTrue(state.isExpanded(query: ""))
    }

    func testClearingTheSearchForgetsACloseMadeDuringIt() {
        var state = AdvancedDisclosureState()
        state.setExpanded(false, query: "glow")
        state.searchChanged(to: "")
        XCTAssertTrue(state.isExpanded(query: "glow"))
    }

    func testTypingKeepsACloseForTheSameSearch() {
        var state = AdvancedDisclosureState()
        state.setExpanded(false, query: "glow")
        state.searchChanged(to: "glow ")
        XCTAssertFalse(state.isExpanded(query: "glow"))
    }

    func testReopeningDuringASearchClearsTheOverride() {
        var state = AdvancedDisclosureState()
        state.setExpanded(false, query: "glow")
        state.setExpanded(true, query: "glow")
        XCTAssertTrue(state.isExpanded(query: "glow"))
        XCTAssertFalse(state.isExpanded(query: ""))
    }
}

final class AdvancedKeywordTests: XCTestCase {
    func testSearchLandsOnTheOptionsUnderAdvanced() {
        XCTAssertEqual(SettingsIndex.panes(matching: "volume steps"), [.activities])
        XCTAssertEqual(SettingsIndex.panes(matching: "widget rows"), [.shelf])
        XCTAssertEqual(SettingsIndex.panes(matching: "glow reach"), [.appearance])
        XCTAssertEqual(SettingsIndex.panes(matching: "pointer effect strength"), [.appearance])
    }

    func testAdvancedFindsEveryPaneWithAnAdvancedSection() {
        let withAdvanced = SettingsPaneID.allCases.filter { !$0.advancedKeywords.isEmpty }
        XCTAssertEqual(withAdvanced, [.notch, .appearance, .activities, .shelf])
        XCTAssertEqual(SettingsIndex.panes(matching: "advanced"), withAdvanced)
    }

    func testEveryAdvancedKeywordFindsItsPane() {
        for pane in SettingsPaneID.allCases {
            for keyword in pane.advancedKeywords {
                XCTAssertTrue(SettingsIndex.panes(matching: keyword).contains(pane), "\(keyword) -> \(pane)")
            }
        }
    }
}
