import XCTest

@testable import WispCore

final class SettingsIndexTests: XCTestCase {
    func testEmptyQueryShowsEveryPane() {
        XCTAssertEqual(SettingsIndex.panes(matching: ""), SettingsPaneID.allCases)
        XCTAssertEqual(SettingsIndex.panes(matching: "   "), SettingsPaneID.allCases)
    }

    func testKeywordsFindTheirPane() {
        XCTAssertEqual(SettingsIndex.panes(matching: "glass"), [.appearance])
        XCTAssertEqual(SettingsIndex.panes(matching: "download progress"), [.activities])
        XCTAssertEqual(SettingsIndex.panes(matching: "claude"), [.agents])
        XCTAssertEqual(SettingsIndex.panes(matching: "pocket"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "dnd"), [.widgets])
        XCTAssertEqual(SettingsIndex.panes(matching: "do not disturb"), [.widgets])
        XCTAssertEqual(SettingsIndex.panes(matching: "spend"), [.agents])
        XCTAssertTrue(SettingsIndex.panes(matching: "sound").contains(.agents))
        XCTAssertEqual(SettingsIndex.panes(matching: "lyrics"), [.activities])
        XCTAssertEqual(SettingsIndex.panes(matching: "bubbles"), [.activities])
        XCTAssertTrue(SettingsIndex.panes(matching: "meeting").contains(.activities))
        XCTAssertTrue(SettingsIndex.panes(matching: "caps lock").contains(.general))
        XCTAssertEqual(SettingsIndex.panes(matching: "update"), [.about])
        XCTAssertEqual(SettingsIndex.panes(matching: "sparkle release"), [.about])
        XCTAssertEqual(SettingsIndex.panes(matching: "dismiss"), [.notifications])
        XCTAssertEqual(SettingsIndex.panes(matching: "rate limit"), [.agents])
        XCTAssertEqual(SettingsIndex.panes(matching: "always allow"), [.agents])
        XCTAssertTrue(SettingsIndex.panes(matching: "rules").contains(.agents))
        XCTAssertTrue(SettingsIndex.panes(matching: "stay on screen").contains(.notifications))
        XCTAssertEqual(SettingsIndex.panes(matching: "dynamic island"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "radial"), [.ring])
        XCTAssertEqual(SettingsIndex.panes(matching: "form"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "open as window"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "minimise"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "sidebar"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "check for updates"), [.about])
        XCTAssertEqual(SettingsIndex.panes(matching: "mouse button"), [.ring])
    }

    func testTitlesMatchCaseAndAccentInsensitively() {
        XCTAssertEqual(SettingsIndex.panes(matching: "CLIPBOARD").first, .clipboard)
        XCTAssertTrue(SettingsIndex.panes(matching: "notch").contains(.notch))
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
            SetupHealth.needed(notifications: false, calendarWidgets: false, mirror: false, dictation: false),
            ["accessibility"])
        XCTAssertEqual(
            SetupHealth.needed(notifications: true, calendarWidgets: true, mirror: true, dictation: true),
            ["accessibility", "fullDiskAccess", "calendars", "camera", "microphone", "speechRecognition"])
    }

    func testFindsTheNewAppearanceAndHUDOptions() {
        XCTAssertEqual(SettingsIndex.panes(matching: "theme").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "wallpaper").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "confetti").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "sound pack").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "pet").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "preset").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "roundness").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "look").first, .appearance)
        XCTAssertEqual(SettingsIndex.panes(matching: "swipe").first, .notch)
        XCTAssertEqual(SettingsIndex.panes(matching: "position").first, .notch)
        XCTAssertEqual(SettingsIndex.panes(matching: "bottom").first, .notch)
        XCTAssertEqual(SettingsIndex.panes(matching: "volume steps").first, .activities)
        XCTAssertEqual(SettingsIndex.panes(matching: "menu bar").first, .general)
        XCTAssertTrue(SettingsIndex.panes(matching: "timer length").contains(.widgets))
    }

    func testAccessoryBatteriesAreFound() {
        XCTAssertTrue(SettingsIndex.panes(matching: "magic mouse").contains(.activities))
        XCTAssertTrue(SettingsIndex.panes(matching: "trackpad battery").contains(.activities))
        XCTAssertTrue(SettingsIndex.panes(matching: "keyboard").contains(.activities))
    }

    func testPhonePaneIsFound() {
        XCTAssertEqual(SettingsIndex.panes(matching: "ntfy"), [.phone])
        XCTAssertEqual(SettingsIndex.panes(matching: "apple watch"), [.phone])
        XCTAssertTrue(SettingsIndex.panes(matching: "push").contains(.phone))
    }

    func testCloudAgentsAreFound() {
        XCTAssertEqual(SettingsIndex.panes(matching: "codex cloud"), [.agents])
        XCTAssertEqual(SettingsIndex.panes(matching: "background agent"), [.agents])
        XCTAssertTrue(SettingsIndex.panes(matching: "copilot").contains(.agents))
    }

    func testAIPaneIsFound() {
        XCTAssertEqual(SettingsIndex.panes(matching: "ollama"), [.ai])
        XCTAssertEqual(SettingsIndex.panes(matching: "apple intelligence"), [.ai])
        XCTAssertEqual(SettingsIndex.panes(matching: "AI").first, .ai)
        XCTAssertTrue(SettingsIndex.panes(matching: "summarize").contains(.ai))
    }
}
