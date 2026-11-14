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
        XCTAssertEqual(SettingsIndex.panes(matching: "dnd"), [.shelf])
        XCTAssertEqual(SettingsIndex.panes(matching: "do not disturb"), [.shelf])
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
        XCTAssertTrue(SettingsIndex.panes(matching: "warn at").contains(.agents))
        XCTAssertEqual(SettingsIndex.panes(matching: "critical at"), [.agents])
        XCTAssertTrue(SettingsIndex.panes(matching: "context colour").contains(.agents))
        XCTAssertTrue(SettingsIndex.panes(matching: "rules").contains(.agents))
        XCTAssertTrue(SettingsIndex.panes(matching: "stay on screen").contains(.notifications))
        XCTAssertEqual(SettingsIndex.panes(matching: "dynamic island"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "radial"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "form"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "open as window"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "minimise"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "sidebar"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "check for updates"), [.about])
        XCTAssertEqual(SettingsIndex.panes(matching: "mouse button"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "quick add"), [.notch, .shelf])
        XCTAssertTrue(SettingsIndex.panes(matching: "reminders").contains(.permissions))
        XCTAssertEqual(SettingsIndex.panes(matching: "session switcher"), [.general])
        XCTAssertEqual(SettingsIndex.panes(matching: "hyper g").first, .general)
        XCTAssertEqual(SettingsIndex.panes(matching: "activity map"), [.agents])
        XCTAssertEqual(SettingsIndex.panes(matching: "limit reset"), [.agents])
    }

    func testAppearanceControlsAreFoundByNewAndOldNames() {
        for query in [
            "edge highlight", "glass edge", "effects", "finish", "shell", "number style", "numbers in",
            "accent follows", "playing album", "change colour through the day", "through the day",
            "beside the closed notch", "while idle", "match the desktop picture", "confetti",
        ] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .appearance, query)
        }
        XCTAssertTrue(SettingsIndex.panes(matching: "shape").contains(.appearance))
        XCTAssertTrue(SettingsIndex.panes(matching: "shape").contains(.notch))
    }

    func testLiveActivitiesControlsAreFoundByNewAndOldNames() {
        for query in [
            "use wisp for these pop-ups", "pop-ups", "replace system overlays", "show more than one activity at once",
            "split extra activities", "focus changes", "show focus changes", "battery warning level",
            "first bubble", "level bars", "google meet",
        ] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .activities, query)
        }
        // Focus changes moved from Notifications, so that name still finds them.
        XCTAssertTrue(SettingsIndex.panes(matching: "notifications focus").contains(.activities))
        XCTAssertFalse(SettingsIndex.panes(matching: "focus").contains(.notifications))
    }

    func testTheFocusButtonShortcutIsFoundByNewAndOldNames() {
        for query in ["focus button runs this shortcut", "focus button", "do not disturb toggle runs"] {
            XCTAssertEqual(SettingsIndex.panes(matching: query), [.shelf], query)
        }
    }

    func testRingControlsAreFoundInNotch() {
        for query in ["ring", "edit ring", "per app", "segments", "middle click"] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .notch, query)
        }
        XCTAssertTrue(SettingsIndex.panes(matching: "hyper r").contains(.notch))
    }

    func testNotchControlsAreFoundByNewAndOldNames() {
        for query in [
            "displays without a notch", "floating island", "don't show", "show on external displays",
            "dynamic island detection", "this mac has a dynamic island", "displays", "each display", "move back",
            "advanced",
        ] {
            XCTAssertTrue(SettingsIndex.panes(matching: query).contains(.notch), query)
        }
        XCTAssertEqual(SettingsIndex.panes(matching: "dynamic island detection"), [.notch])
        XCTAssertEqual(SettingsIndex.panes(matching: "each display"), [.notch])
    }

    func testKeyboardShortcutsAreFoundInGeneral() {
        for query in [
            "keyboard shortcuts", "shortcuts", "allow or deny", "hyper y", "switch profile", "right-click the notch",
            "pick an answer",
        ] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .general, query)
        }
        // The list moved from About.
        XCTAssertFalse(SettingsIndex.panes(matching: "keyboard shortcuts").contains(.about))
        XCTAssertFalse(SettingsIndex.panes(matching: "hyper y").contains(.about))
    }

    func testGeneralAdvancedOptionsAreFound() {
        for query in ["show wisp in the menu bar", "caps lock on its own", "quick press"] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .general, query)
        }
        XCTAssertTrue(SettingsIndex.panes(matching: "advanced").contains(.general))
    }

    func testDiagnosticsAreFoundInAbout() {
        for query in ["copy diagnostics", "diagnostics", "bug report", "copy display info", "display info"] {
            XCTAssertEqual(SettingsIndex.panes(matching: query), [.about], query)
        }
    }

    func testTheSidebarHasTenPanes() {
        XCTAssertEqual(SettingsSection.wisp.panes, [.general, .notch, .appearance])
        XCTAssertEqual(SettingsSection.system.panes, [.permissions, .about])
        XCTAssertEqual(SettingsPaneID.allCases.count, 10)
        XCTAssertEqual(
            SettingsPaneID.allCases.map(\.title),
            [
                "General", "Notch", "Appearance", "Live Activities", "Shelf", "Notifications", "Agents", "AI",
                "Permissions", "About",
            ])
    }

    func testApostrophesAreOptional() {
        for query in ["don't show", "dont show", "don\u{2019}t show", "DONT SHOW"] {
            XCTAssertTrue(SettingsIndex.panes(matching: query).contains(.notch), query)
        }
    }

    func testTheRingPaneIsGone() {
        XCTAssertNil(SettingsPaneID(rawValue: "ring"))
        XCTAssertFalse(SettingsPaneID.allCases.map(\.title).contains("Ring"))
    }

    func testAStoredPaneReopens() {
        XCTAssertEqual(SettingsPaneID.restoring("notch"), .notch)
        XCTAssertEqual(SettingsPaneID.restoring("agents"), .agents)
        for pane in SettingsPaneID.allCases {
            XCTAssertEqual(SettingsPaneID.restoring(pane.rawValue), pane)
        }
    }

    func testTheRingPaneReopensAsNotch() {
        XCTAssertEqual(SettingsPaneID.restoring("ring"), .notch)
    }

    func testShelfReplacesWidgetsClipboardAndProfiles() {
        // Shelf keeps the Widgets pane's stored value, so a saved "widgets" still opens it.
        XCTAssertEqual(SettingsPaneID.shelf.rawValue, "widgets")
        XCTAssertEqual(SettingsPaneID.shelf.title, "Shelf")
        XCTAssertNil(SettingsPaneID(rawValue: "clipboard"))
        XCTAssertNil(SettingsPaneID(rawValue: "profiles"))
        let titles = SettingsPaneID.allCases.map(\.title)
        for old in ["Widgets", "Clipboard", "Profiles"] {
            XCTAssertFalse(titles.contains(old), old)
        }
    }

    func testTheClipboardAndProfilesPanesReopenAsShelf() {
        XCTAssertEqual(SettingsPaneID.restoring("widgets"), .shelf)
        XCTAssertEqual(SettingsPaneID.restoring("clipboard"), .shelf)
        XCTAssertEqual(SettingsPaneID.restoring("profiles"), .shelf)
    }

    func testShelfControlsAreFoundByNewAndOldNames() {
        for query in [
            "widgets", "clipboard", "profiles", "clipboard history", "keep up to", "pinned", "command output",
            "run every", "profile look", "look for", "switch profiles automatically", "save current setup",
            "world clocks", "day progress",
        ] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .shelf, query)
        }
        // Script was the old name for Command output; Notch's drop actions run scripts too.
        XCTAssertTrue(SettingsIndex.panes(matching: "script").contains(.shelf))
        // The profile look moved here from Appearance.
        XCTAssertFalse(SettingsIndex.panes(matching: "profile look").contains(.appearance))
    }

    func testTheSidebarHasWispFeaturesAndSystem() {
        XCTAssertEqual(SettingsSection.allCases.map(\.title), ["Wisp", "Features", "System"])
        XCTAssertEqual(SettingsSection.features.panes, [.activities, .shelf, .notifications, .agents, .ai])
    }

    func testAMissingOrUnknownPaneOpensGeneral() {
        XCTAssertEqual(SettingsPaneID.restoring(nil), .general)
        XCTAssertEqual(SettingsPaneID.restoring(""), .general)
        XCTAssertEqual(SettingsPaneID.restoring("Ring"), .general)
        XCTAssertEqual(SettingsPaneID.restoring("nonsense"), .general)
    }

    func testPermissionSoundLandsOnAgents() {
        XCTAssertEqual(SettingsIndex.panes(matching: "permission sound").first, .agents)
    }

    func testQuietHoursAndTheAwayCardLandOnAgents() {
        for query in ["quiet hours", "while you were away", "away summary", "overnight"] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .agents, query)
        }
    }

    func testTitlesMatchCaseAndAccentInsensitively() {
        XCTAssertEqual(SettingsIndex.panes(matching: "SHELF").first, .shelf)
        XCTAssertTrue(SettingsIndex.panes(matching: "notch").contains(.notch))
        XCTAssertEqual(SettingsIndex.panes(matching: "shélf").first, .shelf)
    }

    func testEveryWordMustMatch() {
        XCTAssertEqual(SettingsIndex.panes(matching: "world clocks"), [.shelf])
        XCTAssertTrue(SettingsIndex.panes(matching: "glass zebra").isEmpty)
    }

    func testWindowPageSettingsAreFound() {
        XCTAssertTrue(SettingsIndex.panes(matching: "working hours").contains(.shelf))
        XCTAssertTrue(SettingsIndex.panes(matching: "time zone").contains(.shelf))
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
        XCTAssertEqual(
            SetupHealth.needed(
                notifications: false, calendarWidgets: false, mirror: false, dictation: false, appVolume: true),
            ["accessibility", "systemAudio"])
    }

    func testFindsAppVolumeAndUpNext() {
        XCTAssertEqual(SettingsIndex.panes(matching: "app volume").first, .activities)
        XCTAssertEqual(SettingsIndex.panes(matching: "up next").first, .activities)
        XCTAssertEqual(SettingsIndex.panes(matching: "system audio recording").first, .activities)
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
        XCTAssertTrue(SettingsIndex.panes(matching: "timer length").contains(.shelf))
    }

    func testAccessoryBatteriesAreFound() {
        XCTAssertTrue(SettingsIndex.panes(matching: "magic mouse").contains(.activities))
        XCTAssertTrue(SettingsIndex.panes(matching: "trackpad battery").contains(.activities))
        XCTAssertTrue(SettingsIndex.panes(matching: "keyboard").contains(.activities))
    }

    func testPhoneAlertsAreFoundInAgents() {
        XCTAssertEqual(SettingsIndex.panes(matching: "ntfy"), [.agents])
        XCTAssertEqual(SettingsIndex.panes(matching: "apple watch"), [.agents])
        XCTAssertTrue(SettingsIndex.panes(matching: "push").contains(.agents))
        // Phone had its own pane; its name stays a keyword. Headphones and microphone match it too.
        XCTAssertTrue(SettingsIndex.panes(matching: "phone").contains(.agents))
        XCTAssertEqual(SettingsIndex.panes(matching: "phone alerts"), [.agents])
    }

    func testThePhonePaneIsGone() {
        XCTAssertNil(SettingsPaneID(rawValue: "phone"))
        XCTAssertFalse(SettingsPaneID.allCases.map(\.title).contains("Phone"))
    }

    func testThePhonePaneReopensAsAgents() {
        XCTAssertEqual(SettingsPaneID.restoring("phone"), .agents)
    }

    func testAgentsControlsAreFoundByNewAndOldNames() {
        for query in [
            "status line under claude code's prompt", "status line", "keep mine", "terminal bar",
            "show what agents are doing", "tool activity", "your own ntfy server", "protected server",
            "add the command or file name", "include details", "away after", "access token", "reply token",
            "wait for an answer", "send agent alerts to my phone", "keep session history",
            "summarise finished sessions", "last 7 days", "command-line tool",
        ] {
            XCTAssertEqual(SettingsIndex.panes(matching: query).first, .agents, query)
        }
        // The clipboard has a Clear history button too.
        XCTAssertTrue(SettingsIndex.panes(matching: "clear history").contains(.agents))
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

    func testAIClipboardActionsAreFound() {
        XCTAssertEqual(SettingsIndex.panes(matching: "translate to"), [.ai])
        XCTAssertTrue(SettingsIndex.panes(matching: "selected text").contains(.ai))
        XCTAssertTrue(SettingsIndex.panes(matching: "ai action").contains(.notch))
    }

    func testLabelsOnScreenAreFound() {
        XCTAssertTrue(SettingsIndex.panes(matching: "now playing").contains(.activities))
        XCTAssertTrue(SettingsIndex.panes(matching: "reduce motion").contains(.appearance))
        XCTAssertTrue(SettingsIndex.panes(matching: "page switcher").contains(.appearance))
        XCTAssertTrue(SettingsIndex.panes(matching: "full disk access").contains(.notifications))
        XCTAssertTrue(SettingsIndex.panes(matching: "engine").contains(.ai))
    }
}
