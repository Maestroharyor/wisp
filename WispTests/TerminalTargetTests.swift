import XCTest

@testable import WispCore

final class TerminalContextTests: XCTestCase {
    func testTakesOnlyTheKnownVariables() {
        let context = TerminalContext(
            environment: [
                "TMUX": "/private/tmp/tmux-501/default,4242,0", "TMUX_PANE": "%3",
                "ITERM_SESSION_ID": "w0t1p0:6C1C2D0E-0000-4000-8000-000000000001", "TERM_PROGRAM": "tmux",
                "HOME": "/Users/someone", "ANTHROPIC_API_KEY": "secret",
            ], tty: "/dev/ttys004")
        XCTAssertEqual(context.tmux, "/private/tmp/tmux-501/default,4242,0")
        XCTAssertEqual(context.tmuxPane, "%3")
        XCTAssertEqual(context.termProgram, "tmux")
        XCTAssertEqual(context.tty, "/dev/ttys004")
        let keys = context.json.objectKeys
        XCTAssertEqual(keys, ["ITERM_SESSION_ID", "TERM_PROGRAM", "TMUX", "TMUX_PANE", "tty"])
    }

    func testEmptyAndOverlongValuesAreDropped() {
        let context = TerminalContext(
            environment: ["TMUX_PANE": "", "WEZTERM_PANE": String(repeating: "9", count: 600)], tty: nil)
        XCTAssertTrue(context.isEmpty)
    }

    func testTmuxSocketIsThePartBeforeTheFirstComma() {
        let context = TerminalContext(environment: ["TMUX": "/tmp/tmux-501/work,99,2"], tty: nil)
        XCTAssertEqual(context.tmuxSocket, "/tmp/tmux-501/work")
        XCTAssertNil(TerminalContext(environment: ["TMUX": ",1,0"], tty: nil).tmuxSocket)
    }

    func testITermSessionGUIDIsAfterTheColon() {
        let context = TerminalContext(environment: ["ITERM_SESSION_ID": "w0t1p0:ABC-123"], tty: nil)
        XCTAssertEqual(context.iTermSessionGUID, "ABC-123")
        XCTAssertNil(TerminalContext(environment: ["ITERM_SESSION_ID": "w0t1p0"], tty: nil).iTermSessionGUID)
    }

    func testTTYPathFromDeviceName() {
        XCTAssertEqual(TerminalContext.ttyPath(deviceName: "ttys003"), "/dev/ttys003")
        XCTAssertNil(TerminalContext.ttyPath(deviceName: "??"))
        XCTAssertNil(TerminalContext.ttyPath(deviceName: ""))
        XCTAssertNil(TerminalContext.ttyPath(deviceName: nil))
    }

    func testEnvelopeCarriesTheContextToHooksAndSnapshots() throws {
        let context = TerminalContext(environment: ["WEZTERM_PANE": "7"], tty: "/dev/ttys009")
        let hook = Data(#"{"session_id":"s","cwd":"/a/wisp","hook_event_name":"Stop"}"#.utf8)
        let data = try XCTUnwrap(
            AgentProtocol.envelope(kind: .hook, source: .claude, terminal: nil, context: context, payload: hook))
        guard case .hook(let event) = try AgentProtocol.decode(data) else { return XCTFail("not a hook") }
        XCTAssertEqual(event.terminalContext, context)

        let line = Data(#"{"session_id":"s"}"#.utf8)
        let lineData = try XCTUnwrap(
            AgentProtocol.envelope(kind: .statusline, source: .claude, terminal: nil, context: context, payload: line))
        guard case .statusline(let snapshot, _, _) = try AgentProtocol.decode(lineData) else {
            return XCTFail("not a statusline")
        }
        XCTAssertEqual(snapshot.terminalContext, context)
    }

    func testEmptyContextIsLeftOutOfTheEnvelope() throws {
        let hook = Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8)
        let data = try XCTUnwrap(
            AgentProtocol.envelope(
                kind: .hook, source: .claude, terminal: nil, context: TerminalContext(environment: [:], tty: nil),
                payload: hook))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertNil(json[TerminalContext.envelopeKey])
    }

    func testUnknownContextKeysAndWrongTypesAreIgnored() throws {
        let data = Data(
            #"{"v":1,"kind":"hook","payload":{"session_id":"s","hook_event_name":"Stop"},"terminalContext":{"TMUX_PANE":3,"tty":"/dev/ttys001","NEW":"x"}}"#
                .utf8)
        guard case .hook(let event) = try AgentProtocol.decode(data) else { return XCTFail("not a hook") }
        XCTAssertEqual(event.terminalContext?.tty, "/dev/ttys001")
        XCTAssertNil(event.terminalContext?.tmuxPane)
    }

    func testSessionKeepsTheLatestContext() {
        var sessions = AgentSessions()
        let first = TerminalContext(environment: [:], tty: "/dev/ttys001")
        sessions.apply(event(context: first), at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(sessions.session("s")?.terminalContext, first)
        sessions.apply(event(context: nil), at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(sessions.session("s")?.terminalContext, first)
    }

    private func event(context: TerminalContext?) -> AgentEvent {
        let json: JSONValue = .object([
            "session_id": .string("s"), "cwd": .string("/a/wisp"), "hook_event_name": .string("UserPromptSubmit"),
        ])
        var event = AgentEvent(json: json, source: .claude, terminal: nil)
        event.terminalContext = context
        return event
    }
}

final class TerminalTargetTests: XCTestCase {
    private let iTerm = "com.googlecode.iterm2"

    func testTmuxPaneComesFirstAndHostIdsInsideTmuxAreNotTrusted() {
        let context = TerminalContext(
            environment: ["TMUX": "/tmp/tmux-501/default,1,0", "TMUX_PANE": "%5", "ITERM_SESSION_ID": "w0t0p0:OLD"],
            tty: "/dev/ttys010")
        let target = TerminalTarget(context: context, bundleID: iTerm, cwd: "/a")
        XCTAssertEqual(target.tmux, TerminalTarget.TmuxPane(socket: "/tmp/tmux-501/default", pane: "%5"))
        // The pane's tty and a stale session id belong to tmux, not the outer tab.
        XCTAssertNil(target.tab)
        XCTAssertEqual(target.strategy, .tmuxPane)
        XCTAssertEqual(target.withClientTTY("/dev/ttys002").tab, .iTermTTY("/dev/ttys002"))
    }

    func testITermBySessionIdThenTTY() {
        let byID = TerminalContext(environment: ["ITERM_SESSION_ID": "w0t2p1:GUID-1"], tty: "/dev/ttys001")
        XCTAssertEqual(TerminalTarget(context: byID, bundleID: iTerm, cwd: "").tab, .iTermSession("GUID-1"))
        let byTTY = TerminalContext(environment: [:], tty: "/dev/ttys001")
        XCTAssertEqual(TerminalTarget(context: byTTY, bundleID: iTerm, cwd: "").tab, .iTermTTY("/dev/ttys001"))
    }

    func testHostTabsByTerminal() {
        let context = TerminalContext(environment: ["WEZTERM_PANE": "12", "KITTY_WINDOW_ID": "3"], tty: "/dev/ttys7")
        XCTAssertEqual(
            TerminalTarget(context: context, bundleID: "com.apple.Terminal", cwd: "").tab, .terminalApp("/dev/ttys7"))
        XCTAssertEqual(
            TerminalTarget(context: context, bundleID: "com.mitchellh.ghostty", cwd: "").tab, .ghostty("/dev/ttys7"))
        XCTAssertEqual(
            TerminalTarget(context: context, bundleID: "com.github.wez.wezterm", cwd: "").tab, .wezterm(pane: "12"))
        // Kitty needs a remote control socket Wisp isn't told about, so it's only activated.
        let kitty = TerminalTarget(context: context, bundleID: "net.kovidgoyal.kitty", cwd: "")
        XCTAssertNil(kitty.tab)
        XCTAssertEqual(kitty.strategy, .activateApp)
        // Editors have no tab Wisp can pick.
        XCTAssertNil(TerminalTarget(context: context, bundleID: "com.microsoft.VSCode", cwd: "").tab)
    }

    func testTmuxIsSkippedInsideAnEditorThatInheritedIt() {
        let context = TerminalContext(
            environment: ["TMUX": "/tmp/s,1,0", "TMUX_PANE": "%1"], tty: "/dev/ttys008")
        let editor = TerminalTarget(context: context, bundleID: "com.microsoft.VSCode", cwd: "")
        XCTAssertNil(editor.tmux)
        XCTAssertEqual(editor.strategy, .activateApp)
        XCTAssertNotNil(TerminalTarget(context: context, bundleID: "com.mitchellh.ghostty", cwd: "").tmux)
        // Unknown host (no bundle id): tmux is the only lead.
        XCTAssertNotNil(TerminalTarget(context: context, bundleID: nil, cwd: "").tmux)
    }

    func testTmuxIsDroppedWhenThePaneIsNotTheAgentsTerminal() {
        let context = TerminalContext(
            environment: ["TMUX": "/tmp/s,1,0", "TMUX_PANE": "%1"], tty: "/dev/ttys008")
        let target = TerminalTarget(context: context, bundleID: "com.mitchellh.ghostty", cwd: "")
        XCTAssertTrue(target.paneMatches(paneTTY: "/dev/ttys008"))
        XCTAssertFalse(target.paneMatches(paneTTY: "/dev/ttys002"))
        // A shell started from tmux carried TMUX along: the agent's own tty is the tab.
        let without = target.withoutTmux()
        XCTAssertNil(without.tmux)
        XCTAssertEqual(without.tab, .ghostty("/dev/ttys008"))
        // Without the agent's tty there's nothing to compare, so the pane is trusted.
        let noTTY = TerminalTarget(
            context: TerminalContext(environment: ["TMUX": "/tmp/s,1,0", "TMUX_PANE": "%1"], tty: nil),
            bundleID: nil, cwd: "")
        XCTAssertTrue(noTTY.paneMatches(paneTTY: "/dev/ttys002"))
    }

    func testTmuxPaneInfo() {
        XCTAssertEqual(
            TmuxClients.paneInfo("/dev/ttys008\twork\n"), TmuxClients.PaneInfo(session: "work", tty: "/dev/ttys008"))
        // The tty comes first because a session name can hold a tab.
        XCTAssertEqual(TmuxClients.paneInfo("/dev/ttys008\ta\tb")?.session, "a\tb")
        XCTAssertNil(TmuxClients.paneInfo(""))
        XCTAssertNil(TmuxClients.paneInfo("/dev/ttys008"))
        XCTAssertNil(TmuxClients.paneInfo("work\t/dev/ttys008"))
    }

    func testWeztermPaneIdMustBeNumeric() {
        let context = TerminalContext(environment: ["WEZTERM_PANE": "1; rm"], tty: nil)
        XCTAssertNil(TerminalTarget(context: context, bundleID: "com.github.wez.wezterm", cwd: "").tab)
    }

    func testTmuxPaneMustLookLikeAPaneId() {
        let context = TerminalContext(environment: ["TMUX": "/tmp/s,1,0", "TMUX_PANE": "-t evil"], tty: nil)
        XCTAssertNil(TerminalTarget(context: context, bundleID: nil, cwd: "").tmux)
    }

    func testBundleIsInferredWhenTheHelperCouldNotNameIt() {
        let context = TerminalContext(environment: ["ITERM_SESSION_ID": "w0t0p0:G"], tty: nil)
        let target = TerminalTarget(context: context, bundleID: nil, cwd: "")
        XCTAssertEqual(target.bundleID, iTerm)
        XCTAssertEqual(target.tab, .iTermSession("G"))
    }

    func testFallsBackToActivatingThenOpeningTheFolder() {
        XCTAssertEqual(TerminalTarget(context: nil, bundleID: iTerm, cwd: "/a").strategy, .activateApp)
        XCTAssertEqual(TerminalTarget(context: nil, bundleID: nil, cwd: "/a").strategy, .openFolder)
        XCTAssertEqual(TerminalTarget(context: nil, bundleID: nil, cwd: "").strategy, .nothing)
    }

    func testTmuxCommands() {
        let pane = TerminalTarget.TmuxPane(socket: "/tmp/s", pane: "%5")
        XCTAssertEqual(pane.arguments(["select-pane", "-t", "%5"]), ["-S", "/tmp/s", "select-pane", "-t", "%5"])
        XCTAssertEqual(
            TerminalTarget.TmuxPane(socket: nil, pane: "%5").arguments(["select-window", "-t", "%5"]),
            ["select-window", "-t", "%5"])
    }

    func testTmuxClientPicksTheMostRecentClientOnThePanesSession() {
        let output = "/dev/ttys001\twork\t100\n/dev/ttys002\twork\t300\n/dev/ttys003\tplay\t500\n"
        XCTAssertEqual(
            TmuxClients.pick(listOutput: output, session: "work"),
            TmuxClients.Choice(tty: "/dev/ttys002", switchTo: false))
        // Nobody watches that session: the most recent client switches to it.
        XCTAssertEqual(
            TmuxClients.pick(listOutput: output, session: "other"),
            TmuxClients.Choice(tty: "/dev/ttys003", switchTo: true))
        XCTAssertNil(TmuxClients.pick(listOutput: "", session: "work"))
    }
}

final class TerminalScriptTests: XCTestCase {
    func testScriptsQuoteTheirArguments() {
        let script = TerminalScript.iTerm(sessionID: #"a"b\c"#)
        XCTAssertTrue(script.contains(#"is "a\"b\\c""#))
        XCTAssertTrue(script.contains(#"application id "com.googlecode.iterm2""#))
    }

    func testEachTerminalSelectsByTheRightProperty() {
        XCTAssertTrue(TerminalScript.iTerm(tty: "/dev/ttys1").contains(#"tty of s is "/dev/ttys1""#))
        XCTAssertTrue(TerminalScript.terminalApp(tty: "/dev/ttys1").contains(#"tty of t is "/dev/ttys1""#))
        XCTAssertTrue(TerminalScript.terminalApp(tty: "/dev/ttys1").contains("set selected of t to true"))
        XCTAssertTrue(TerminalScript.ghostty(tty: "/dev/ttys1").contains(#"tty of t is "/dev/ttys1""#))
        XCTAssertTrue(TerminalScript.ghostty(tty: "/dev/ttys1").contains("focus t"))
    }

    func testScriptsReportWhetherTheyFoundTheTab() {
        for script in [
            TerminalScript.iTerm(sessionID: "x"), TerminalScript.terminalApp(tty: "x"),
            TerminalScript.ghostty(tty: "x"),
        ] {
            XCTAssertTrue(script.contains(#"return "\#(TerminalScript.found)""#))
        }
    }
}

extension JSONValue {
    fileprivate var objectKeys: [String] {
        guard case .object(let fields) = self else { return [] }
        return fields.keys.sorted()
    }
}

final class TerminalToolsTests: XCTestCase {
    func testLoginPathFirstThenUsualFoldersWithoutRepeats() {
        let found = TerminalTools.candidates("tmux", path: "~/bin:/opt/homebrew/bin:relative", home: "/Users/a")
        XCTAssertEqual(
            found,
            [
                "/Users/a/bin/tmux", "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/Users/a/.local/bin/tmux",
                "/usr/bin/tmux",
            ])
        XCTAssertEqual(TerminalTools.candidates("x", path: nil, home: "/h").first, "/opt/homebrew/bin/x")
    }
}
