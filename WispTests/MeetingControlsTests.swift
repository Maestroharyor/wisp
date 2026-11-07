import XCTest

@testable import WispCore

final class MeetingControlsTests: XCTestCase {
    // MARK: Picking the app

    func testZoomHoldingTheMicIsDriven() {
        XCTAssertEqual(MeetingControls.app(inputApps: ["us.zoom.xos"], meetWindows: []), .zoom)
    }

    func testNewTeamsIsDriven() {
        XCTAssertEqual(MeetingControls.app(inputApps: ["com.microsoft.teams2"], meetWindows: []), .teams)
    }

    func testOtherCallAppsShowNoControls() {
        for id in ["com.apple.FaceTime", "com.microsoft.teams", "com.tinyspeck.slackmacgap", "com.hnc.Discord"] {
            XCTAssertNil(MeetingControls.app(inputApps: [id], meetWindows: []), id)
        }
    }

    func testABrowserNeedsAMeetWindow() {
        XCTAssertNil(MeetingControls.app(inputApps: ["com.google.Chrome"], meetWindows: []))
        XCTAssertEqual(
            MeetingControls.app(inputApps: ["com.google.Chrome"], meetWindows: ["com.google.Chrome"]),
            .meet(browser: "com.google.Chrome"))
    }

    func testABrowserHelperCountsForItsBrowser() {
        XCTAssertEqual(
            MeetingControls.app(inputApps: ["com.brave.Browser.helper"], meetWindows: ["com.brave.Browser"]),
            .meet(browser: "com.brave.Browser"))
    }

    func testAMeetWindowWithoutTheMicIsNotACall() {
        XCTAssertNil(MeetingControls.app(inputApps: ["com.apple.VoiceMemos"], meetWindows: ["com.google.Chrome"]))
    }

    func testSafariIsNotDriven() {
        XCTAssertNil(MeetingControls.app(inputApps: ["com.apple.Safari"], meetWindows: ["com.apple.Safari"]))
    }

    func testACallAppWinsOverABrowser() {
        let ids = ["com.google.Chrome", "us.zoom.xos"]
        XCTAssertEqual(MeetingControls.app(inputApps: ids, meetWindows: ["com.google.Chrome"]), .zoom)
    }

    // MARK: Meet windows

    func testMeetWindowByURL() {
        XCTAssertTrue(MeetingControls.isMeetWindow(title: "Anything", url: "https://meet.google.com/abc-defg-hij"))
        XCTAssertFalse(MeetingControls.isMeetWindow(title: "Meet - abc-defg-hij", url: "https://example.com/meet"))
    }

    func testMeetWindowByTitle() {
        XCTAssertTrue(MeetingControls.isMeetWindow(title: "Meet - abc-defg-hij", url: nil))
        XCTAssertTrue(MeetingControls.isMeetWindow(title: "Meet – Weekly sync", url: nil))
        XCTAssertFalse(MeetingControls.isMeetWindow(title: "Meeting notes - Google Docs", url: nil))
        XCTAssertFalse(MeetingControls.isMeetWindow(title: "Google Meet", url: nil))
        XCTAssertFalse(MeetingControls.isMeetWindow(title: nil, url: nil))
    }

    // MARK: States

    func testZoomStatesComeFromItsMenu() {
        let states = MeetingControls.states(
            for: .zoom, menuTitles: ["Unmute audio", "Start video", "Start share", "Leave meeting", "Invite"])
        XCTAssertEqual(
            states,
            [
                MeetingControlState(control: .mute, engaged: true),
                MeetingControlState(control: .camera, engaged: false),
                MeetingControlState(control: .share, engaged: false),
                MeetingControlState(control: .leave, engaged: false),
            ])
        XCTAssertEqual(states.map(\.label), ["Unmute", "Start video", "Share", "Leave"])
    }

    func testZoomOutsideACallShowsNothing() {
        XCTAssertEqual(MeetingControls.states(for: .zoom, menuTitles: ["About zoom.us", "Settings…"]), [])
    }

    func testOlderTitleCaseAndEllipsesMatch() {
        let states = MeetingControls.states(for: .zoom, menuTitles: ["Mute Audio", "Stop Video", "Stop Share…"])
        XCTAssertEqual(states.map(\.engaged), [false, true, true])
        XCTAssertEqual(states.map(\.label), ["Mute", "Stop video", "Stop share"])
    }

    func testLocalisedZoomTitlesMatch() {
        let german = MeetingControls.states(for: .zoom, menuTitles: ["Stummschaltung für Audio aufheben"])
        XCTAssertEqual(german, [MeetingControlState(control: .mute, engaged: true)])
        let russian = MeetingControls.states(for: .zoom, menuTitles: ["Выключить звук"])
        XCTAssertEqual(russian, [MeetingControlState(control: .mute, engaged: false)])
    }

    func testOnlyControlsInTheMenuShow() {
        let states = MeetingControls.states(for: .zoom, menuTitles: ["Mute audio", "End meeting"])
        XCTAssertEqual(states.map(\.control), [.mute, .leave])
    }

    func testShortcutAppsShowTheirControlsWithoutState() {
        XCTAssertEqual(MeetingControls.states(for: .teams, menuTitles: []).map(\.control), [.mute, .camera, .leave])
        let meet = MeetingControls.states(for: .meet(browser: "com.google.Chrome"), menuTitles: [])
        XCTAssertEqual(meet.map(\.control), [.mute, .camera])
        XCTAssertEqual(meet.map(\.engaged), [nil, nil])
        XCTAssertEqual(meet.map(\.label), ["Mic", "Camera"])
    }

    // MARK: Table

    func testDocumentedShortcuts() {
        XCTAssertEqual(
            MeetingControls.strategy(for: .mute, in: .teams),
            .shortcut(KeyShortcut(keyCode: 0x2E, modifiers: [.command, .shift])))
        XCTAssertEqual(
            MeetingControls.strategy(for: .camera, in: .teams),
            .shortcut(KeyShortcut(keyCode: 0x1F, modifiers: [.command, .shift])))
        XCTAssertEqual(
            MeetingControls.strategy(for: .leave, in: .teams),
            .shortcut(KeyShortcut(keyCode: 0x04, modifiers: [.command, .shift])))
        XCTAssertNil(MeetingControls.strategy(for: .share, in: .teams))
        let meet = MeetingApp.meet(browser: "com.google.Chrome")
        XCTAssertEqual(
            MeetingControls.strategy(for: .mute, in: meet), .shortcut(KeyShortcut(keyCode: 0x02, modifiers: .command)))
        XCTAssertEqual(
            MeetingControls.strategy(for: .camera, in: meet),
            .shortcut(KeyShortcut(keyCode: 0x0E, modifiers: .command)))
        XCTAssertNil(MeetingControls.strategy(for: .leave, in: meet))
    }

    func testIdleAndEngagedTitlesNeverOverlap() {
        for (control, strategy) in MeetingControls.strategies(for: .zoom) {
            guard case .menu(let idle, let engaged) = strategy else { continue }
            let both = Set(idle.map(MeetingControls.normalize)).intersection(engaged.map(MeetingControls.normalize))
            XCTAssertTrue(both.isEmpty, "\(control): \(both)")
        }
    }

    func testATitleDrivesOnlyItsControl() {
        XCTAssertTrue(MeetingControls.menuItem("Unmute Audio", drives: .mute, in: .zoom))
        XCTAssertFalse(MeetingControls.menuItem("Unmute audio", drives: .camera, in: .zoom))
        XCTAssertFalse(MeetingControls.menuItem("Mute audio", drives: .mute, in: .teams))
    }

    func testOnlyZoomReadsTheMenu() {
        XCTAssertTrue(MeetingControls.usesMenu(.zoom))
        XCTAssertFalse(MeetingControls.usesMenu(.teams))
    }

    func testShortcutsAndZoomsLeaveBringTheAppForward() {
        XCTAssertTrue(MeetingControls.bringsForward(.teams, for: .mute))
        XCTAssertTrue(MeetingControls.bringsForward(.meet(browser: "com.google.Chrome"), for: .camera))
        XCTAssertFalse(MeetingControls.bringsForward(.zoom, for: .mute))
        XCTAssertTrue(MeetingControls.bringsForward(.zoom, for: .leave))
        XCTAssertFalse(MeetingControls.bringsForward(.teams, for: .share))
    }

    func testSymbolsFollowState() {
        XCTAssertEqual(MeetingControlState(control: .mute, engaged: true).symbol, "mic.slash.fill")
        XCTAssertEqual(MeetingControlState(control: .camera, engaged: false).symbol, "video.slash.fill")
        XCTAssertEqual(MeetingControlState(control: .leave, engaged: false).symbol, "phone.down.fill")
    }

    func testShortcutButtonsSayTheyOnlyToggle() {
        XCTAssertTrue(MeetingControlState(control: .mute, engaged: nil).help.contains("without confirming"))
        XCTAssertTrue(MeetingControlState(control: .camera, engaged: nil).help.contains("without confirming"))
        XCTAssertEqual(MeetingControlState(control: .mute, engaged: true).help, "Unmute")
    }

    // MARK: Leave confirmation

    func testLeaveNeedsTwoTaps() {
        let start = Date(timeIntervalSince1970: 1000)
        var confirm = LeaveConfirmation()
        XCTAssertEqual(confirm.label(now: start), "Leave")
        XCTAssertFalse(confirm.tap(now: start))
        XCTAssertTrue(confirm.isArmed(now: start.addingTimeInterval(1)))
        XCTAssertEqual(confirm.label(now: start.addingTimeInterval(1)), "Leave?")
        XCTAssertTrue(confirm.tap(now: start.addingTimeInterval(2)))
        XCTAssertFalse(confirm.isArmed(now: start.addingTimeInterval(2)))
    }

    func testLeaveDisarmsAfterThreeSeconds() {
        let start = Date(timeIntervalSince1970: 1000)
        var confirm = LeaveConfirmation()
        XCTAssertFalse(confirm.tap(now: start))
        XCTAssertFalse(confirm.isArmed(now: start.addingTimeInterval(3)))
        XCTAssertEqual(confirm.label(now: start.addingTimeInterval(3)), "Leave")
        // A late second tap only arms it again.
        XCTAssertFalse(confirm.tap(now: start.addingTimeInterval(4)))
        XCTAssertTrue(confirm.tap(now: start.addingTimeInterval(5)))
    }

    func testADoubleClickDoesNotLeave() {
        let start = Date(timeIntervalSince1970: 1000)
        var confirm = LeaveConfirmation()
        XCTAssertFalse(confirm.tap(now: start))
        // Too soon to be a deliberate second tap: nothing sent, still armed.
        XCTAssertFalse(confirm.tap(now: start.addingTimeInterval(0.2)))
        XCTAssertTrue(confirm.isArmed(now: start.addingTimeInterval(0.3)))
        XCTAssertEqual(confirm.armedAt, start)
        XCTAssertTrue(confirm.tap(now: start.addingTimeInterval(0.6)))
    }

    // MARK: Join card

    func testInviteMatchesItsApp() {
        let zoom = URL(string: "https://us02web.zoom.us/j/123")
        let teams = URL(string: "https://teams.microsoft.com/l/meetup-join/abc")
        let teamsLive = URL(string: "https://teams.live.com/meet/123")
        let meet = URL(string: "https://meet.google.com/abc-defg-hij")
        let chrome = MeetingApp.meet(browser: "com.google.Chrome")
        XCTAssertEqual(zoom.map { MeetingControls.invite($0, matches: .zoom) }, true)
        XCTAssertEqual(zoom.map { MeetingControls.invite($0, matches: .teams) }, false)
        XCTAssertEqual(teams.map { MeetingControls.invite($0, matches: .teams) }, true)
        XCTAssertEqual(teamsLive.map { MeetingControls.invite($0, matches: .teams) }, true)
        XCTAssertEqual(teams.map { MeetingControls.invite($0, matches: chrome) }, false)
        XCTAssertEqual(meet.map { MeetingControls.invite($0, matches: chrome) }, true)
        XCTAssertEqual(meet.map { MeetingControls.invite($0, matches: .zoom) }, false)
    }

    func testLookalikeHostsDoNotMatch() {
        let fake = URL(string: "https://zoom.us.example.com/j/1")
        let notMeet = URL(string: "https://meet.google.com.evil.io/x")
        XCTAssertEqual(fake.map { MeetingControls.invite($0, matches: .zoom) }, false)
        XCTAssertEqual(notMeet.map { MeetingControls.invite($0, matches: .meet(browser: "com.google.Chrome")) }, false)
    }

    func testJoinCardNeverOffersLeave() {
        let states = MeetingControls.states(for: .zoom, menuTitles: ["Mute audio", "Stop video", "Leave meeting"])
        XCTAssertEqual(MeetingControls.joinCardStates(states).map(\.control), [.mute, .camera])
    }

    // MARK: Typing shortcuts

    func testMeetNeedsItsTabInTheFocusedWindow() {
        let meet = MeetingApp.meet(browser: "com.google.Chrome")
        XCTAssertTrue(
            MeetingControls.mayType(
                meet, focus: FocusSnapshot(appIsFrontmost: true, windowTitle: "Meet - abc-defg-hij")))
        XCTAssertFalse(
            MeetingControls.mayType(meet, focus: FocusSnapshot(appIsFrontmost: true, windowTitle: "Inbox - Gmail")))
        XCTAssertFalse(
            MeetingControls.mayType(
                meet, focus: FocusSnapshot(appIsFrontmost: false, windowTitle: "Meet - abc-defg-hij")))
    }

    func testNoTypingIntoTheAddressBar() {
        let meet = MeetingApp.meet(browser: "com.google.Chrome")
        let addressBar = FocusSnapshot(
            appIsFrontmost: true, windowURL: "https://meet.google.com/abc-defg-hij", focusedRole: "AXTextField")
        XCTAssertFalse(MeetingControls.mayType(meet, focus: addressBar))
        var inPage = addressBar
        inPage.focusedInWebArea = true
        XCTAssertTrue(MeetingControls.mayType(meet, focus: inPage))
        var button = addressBar
        button.focusedRole = "AXButton"
        XCTAssertTrue(MeetingControls.mayType(meet, focus: button))
    }

    func testASlowSnapshotIsTooOldToTypeOn() {
        let meet = MeetingApp.meet(browser: "com.google.Chrome")
        var focus = FocusSnapshot(appIsFrontmost: true, windowTitle: "Meet - abc-defg-hij")
        focus.readSeconds = 0.15
        XCTAssertTrue(MeetingControls.mayType(meet, focus: focus))
        focus.readSeconds = 0.25
        XCTAssertFalse(MeetingControls.mayType(meet, focus: focus))
    }

    func testTeamsNeedsAFocusedWindowAndZoomIsNeverTyped() {
        XCTAssertFalse(MeetingControls.mayType(.teams, focus: FocusSnapshot(appIsFrontmost: true)))
        XCTAssertTrue(
            MeetingControls.mayType(.teams, focus: FocusSnapshot(appIsFrontmost: true, hasFocusedWindow: true)))
        XCTAssertFalse(
            MeetingControls.mayType(.zoom, focus: FocusSnapshot(appIsFrontmost: true, hasFocusedWindow: true)))
    }

    // MARK: Hand back

    func testHandBackToThePreviousApp() {
        XCTAssertEqual(
            MeetingControls.handBack(
                movedFocus: true, sent: true, control: .mute, previousPID: 10, targetPID: 20, previousWindow: "Notes",
                callWindow: "Meet - x"),
            .app(10))
        // A failed press still gives focus back.
        XCTAssertEqual(
            MeetingControls.handBack(
                movedFocus: true, sent: false, control: .leave, previousPID: 10, targetPID: 20, previousWindow: nil,
                callWindow: nil),
            .app(10))
    }

    func testNoHandBackWhenFocusDidNotMoveOrAfterLeaving() {
        XCTAssertEqual(
            MeetingControls.handBack(
                movedFocus: false, sent: true, control: .mute, previousPID: 10, targetPID: 20, previousWindow: nil,
                callWindow: nil),
            .none)
        XCTAssertEqual(
            MeetingControls.handBack(
                movedFocus: true, sent: true, control: .leave, previousPID: 10, targetPID: 20, previousWindow: nil,
                callWindow: nil),
            .none)
    }

    func testSameBrowserRaisesThePreviousWindow() {
        XCTAssertEqual(
            MeetingControls.handBack(
                movedFocus: true, sent: true, control: .camera, previousPID: 20, targetPID: 20,
                previousWindow: "Inbox - Gmail", callWindow: "Meet - x"),
            .window(title: "Inbox - Gmail"))
        XCTAssertEqual(
            MeetingControls.handBack(
                movedFocus: true, sent: true, control: .camera, previousPID: 20, targetPID: 20,
                previousWindow: "Meet - x", callWindow: "Meet - x"),
            .none)
    }

    func testOnlyShortcutAppsAreOptIn() {
        XCTAssertFalse(MeetingControls.usesShortcuts(.zoom))
        XCTAssertTrue(MeetingControls.usesShortcuts(.teams))
        XCTAssertTrue(MeetingControls.usesShortcuts(.meet(browser: "com.google.Chrome")))
    }
}
