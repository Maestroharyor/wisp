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

extension JSONValue {
    fileprivate var objectKeys: [String] {
        guard case .object(let fields) = self else { return [] }
        return fields.keys.sorted()
    }
}
