import XCTest

@testable import WispCore

final class SettingsIndexTests: XCTestCase {
    func testEmptyQueryShowsEveryPane() {
        XCTAssertEqual(SettingsIndex.panes(matching: ""), SettingsPaneID.allCases)
        XCTAssertEqual(SettingsIndex.panes(matching: "   "), SettingsPaneID.allCases)
    }

    func testKeywordsFindTheirPane() {
        XCTAssertEqual(SettingsIndex.panes(matching: "glass"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "claude"), [.agents])
        XCTAssertTrue(SettingsIndex.panes(matching: "caps lock").contains(.general))
    }

    func testTitlesMatchCaseAndAccentInsensitively() {
        XCTAssertEqual(SettingsIndex.panes(matching: "CLIPBOARD").first, .clipboard)
        XCTAssertTrue(SettingsIndex.panes(matching: "notch & look").contains(.notch))
        XCTAssertEqual(SettingsIndex.panes(matching: "wídgets").first, .widgets)
    }

    func testEveryWordMustMatch() {
        XCTAssertEqual(SettingsIndex.panes(matching: "world clocks"), [.widgets])
        XCTAssertTrue(SettingsIndex.panes(matching: "glass zebra").isEmpty)
    }

    func testEveryPaneBelongsToASectionInOrder() {
        let flattened = SettingsSection.allCases.flatMap(\.panes)
        XCTAssertEqual(flattened, SettingsPaneID.allCases)
    }
}

final class SetupHealthTests: XCTestCase {
    func testMissingKeepsNeededOrderAndSkipsUnknown() {
        let granted: [String: Bool?] = ["accessibility": false, "calendars": true, "automation": nil, "camera": false]
        XCTAssertEqual(
            SetupHealth.missing(granted: granted, needed: ["accessibility", "calendars", "automation", "camera"]),
            ["accessibility", "camera"])
    }

    func testNothingNeededMeansHealthy() {
        XCTAssertEqual(SetupHealth.missing(granted: ["accessibility": false], needed: []), [])
    }

    func testNeededFollowsFeatures() {
        XCTAssertEqual(
            SetupHealth.needed(notifications: false, calendarWidgets: false, mirror: false), ["accessibility"])
        XCTAssertEqual(
            SetupHealth.needed(notifications: true, calendarWidgets: true, mirror: true),
            ["accessibility", "fullDiskAccess", "calendars", "camera"])
    }
}
