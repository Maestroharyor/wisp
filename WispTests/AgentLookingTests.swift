import XCTest

@testable import WispCore

final class AgentLookingTests: XCTestCase {
    private let iTerm = TerminalTarget.iTerm
    private let terminal = TerminalTarget.terminalApp

    // MARK: Looking

    func testAnotherAppInFrontMeansNotLooking() {
        XCTAssertFalse(
            AgentLooking.isLooking(frontmost: "com.apple.Safari", sessionApp: iTerm, sessionTTY: nil, activeTTY: nil))
        XCTAssertFalse(AgentLooking.isLooking(frontmost: nil, sessionApp: iTerm, sessionTTY: nil, activeTTY: nil))
    }

    func testASessionWithoutAKnownAppIsNeverLookedAt() {
        XCTAssertFalse(AgentLooking.isLooking(frontmost: iTerm, sessionApp: nil, sessionTTY: nil, activeTTY: nil))
    }

    func testTheAppInFrontIsEnoughWhenTheTabCantBeKnown() {
        XCTAssertTrue(AgentLooking.isLooking(frontmost: iTerm, sessionApp: iTerm, sessionTTY: nil, activeTTY: nil))
        XCTAssertTrue(
            AgentLooking.isLooking(frontmost: iTerm, sessionApp: iTerm, sessionTTY: "/dev/ttys003", activeTTY: nil))
    }

    func testTheActiveTabMustBeTheSessions() {
        XCTAssertTrue(
            AgentLooking.isLooking(
                frontmost: terminal, sessionApp: terminal, sessionTTY: "/dev/ttys003", activeTTY: "/dev/ttys003"))
        XCTAssertFalse(
            AgentLooking.isLooking(
                frontmost: terminal, sessionApp: terminal, sessionTTY: "/dev/ttys003", activeTTY: "/dev/ttys004"))
    }

    func testAnActiveTTYWithSpacesOrABareNameStillMatches() {
        XCTAssertTrue(
            AgentLooking.isLooking(
                frontmost: terminal, sessionApp: terminal, sessionTTY: "/dev/ttys003", activeTTY: " ttys003\n"))
    }

    // MARK: Probe

    func testOnlyITermAndTerminalTabsCanBeProbed() {
        let context = TerminalContext(environment: [:], tty: "/dev/ttys003")
        XCTAssertEqual(
            AgentLooking.probe(context: context, sessionApp: iTerm),
            AgentLooking.Probe(app: iTerm, tty: "/dev/ttys003"))
        XCTAssertEqual(
            AgentLooking.probe(context: context, sessionApp: terminal),
            AgentLooking.Probe(app: terminal, tty: "/dev/ttys003"))
        XCTAssertNil(AgentLooking.probe(context: context, sessionApp: TerminalTarget.ghostty))
        XCTAssertNil(AgentLooking.probe(context: context, sessionApp: nil))
    }

    func testNoTTYOrATmuxPaneCantBeProbed() {
        XCTAssertNil(AgentLooking.probe(context: nil, sessionApp: iTerm))
        XCTAssertNil(AgentLooking.probe(context: TerminalContext(environment: [:], tty: nil), sessionApp: iTerm))
        // The tab shows the tmux client's tty, never the pane's.
        let tmux = TerminalContext(environment: ["TMUX": "/tmp/tmux-501/default,1,0"], tty: "/dev/ttys003")
        XCTAssertNil(AgentLooking.probe(context: tmux, sessionApp: iTerm))
    }

    func testProbeScriptsReadTheFrontTabOnly() {
        let iTermScript = AgentLooking.Probe(app: iTerm, tty: "/dev/ttys003").script
        XCTAssertTrue(iTermScript.contains("application id \"com.googlecode.iterm2\""))
        XCTAssertTrue(iTermScript.contains("tty of current session of current window"))
        let terminalScript = AgentLooking.Probe(app: terminal, tty: "/dev/ttys003").script
        XCTAssertTrue(terminalScript.contains("application id \"com.apple.Terminal\""))
        XCTAssertTrue(terminalScript.contains("tty of selected tab of front window"))
    }

    func testOnlySessionAlertsCheckForLooking() {
        XCTAssertTrue(AgentLooking.applies(to: .needsYou))
        XCTAssertTrue(AgentLooking.applies(to: .done))
        XCTAssertFalse(AgentLooking.applies(to: .limits))
    }
}
