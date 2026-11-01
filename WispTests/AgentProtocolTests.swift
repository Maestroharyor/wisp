import XCTest

@testable import WispCore

final class AgentProtocolTests: XCTestCase {
    func testHookEnvelopeRoundTrips() throws {
        let payload = Data(#"{"session_id":"s","cwd":"/a/wisp","hook_event_name":"Stop"}"#.utf8)
        let data = try XCTUnwrap(
            AgentProtocol.envelope(kind: .hook, source: .codex, terminal: "com.apple.Terminal", payload: payload))
        guard case .hook(let event) = try AgentProtocol.decode(data) else { return XCTFail("not a hook") }
        XCTAssertEqual(event.kind, .stop)
        XCTAssertEqual(event.source, .codex)
        XCTAssertEqual(event.terminal, "com.apple.Terminal")
        XCTAssertEqual(event.project, "wisp")
    }

    func testStatuslineEnvelope() throws {
        let payload = Data(#"{"session_id":"s","cost":{"total_cost_usd":1.5}}"#.utf8)
        let data = try XCTUnwrap(
            AgentProtocol.envelope(kind: .statusline, source: .claude, terminal: nil, payload: payload))
        guard case .statusline(let snapshot, let source, let terminal) = try AgentProtocol.decode(data) else {
            return XCTFail("not a statusline")
        }
        XCTAssertEqual(snapshot.cost, 1.5)
        XCTAssertEqual(source, .claude)
        XCTAssertNil(terminal)
    }

    func testOriginalTaggedFormatStillDecodes() throws {
        let data = Data(#"{"session_id":"s","hook_event_name":"Stop","wisp_source":"codex"}"#.utf8)
        guard case .hook(let event) = try AgentProtocol.decode(data) else { return XCTFail("not a hook") }
        XCTAssertEqual(event.source, .codex)
    }

    func testNewerVersionsAndUnknownKindsAreUnsupported() throws {
        XCTAssertEqual(
            try AgentProtocol.decode(Data(#"{"v":2,"kind":"hook","payload":{}}"#.utf8)), .unsupported("hook v2"))
        XCTAssertEqual(
            try AgentProtocol.decode(Data(#"{"v":1,"kind":"dance","payload":{}}"#.utf8)), .unsupported("dance v1"))
    }

    func testEnvelopeNeedsAnObject() {
        XCTAssertNil(AgentProtocol.envelope(kind: .hook, source: .claude, terminal: nil, payload: Data("[1]".utf8)))
        XCTAssertNil(AgentProtocol.envelope(kind: .hook, source: .claude, terminal: nil, payload: Data("x".utf8)))
    }
}

final class StatusLineChainTests: XCTestCase {
    private let helper = "/Applications/Wisp.app/Contents/MacOS/wisp-agent"

    private func settings(_ json: String) -> Data { Data(json.utf8) }

    private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    func testInstallsWispsBarWhenThereIsNone() throws {
        let out = try StatusLineChain.install(.wisp, into: settings("{}"), helper: helper)
        XCTAssertEqual(try json(out)["statusLine"]?["command"], .string("'\(helper)' statusline"))
        XCTAssertEqual(try json(out)["statusLine"]?["type"], .string("command"))
        XCTAssertEqual(try StatusLineChain.state(in: out), .wisp(saved: nil))
    }

    func testWispsBarKeepsTheUsersCommandAndOtherKeys() throws {
        let original = settings(#"{"statusLine":{"type":"command","command":"~/bin/bar.sh 'a b'","padding":2}}"#)
        let out = try StatusLineChain.install(.wisp, into: original, helper: helper)
        XCTAssertEqual(try json(out)["statusLine"]?["padding"], .number(2))
        XCTAssertEqual(try StatusLineChain.state(in: out), .wisp(saved: "~/bin/bar.sh 'a b'"))
    }

    func testListenChainsTheUsersBar() throws {
        let original = settings(#"{"statusLine":{"type":"command","command":"echo it's mine"}}"#)
        let out = try StatusLineChain.install(.listen, into: original, helper: helper)
        XCTAssertEqual(try StatusLineChain.state(in: out), .listening(original: "echo it's mine"))
    }

    func testListenWithoutABarIsQuiet() throws {
        let out = try StatusLineChain.install(.listen, into: settings("{}"), helper: helper)
        XCTAssertEqual(try json(out)["statusLine"]?["command"], .string("'\(helper)' statusline --quiet"))
        XCTAssertEqual(try StatusLineChain.state(in: out), .listening(original: nil))
    }

    func testRestoreGivesBackTheExactOriginal() throws {
        let original = settings(
            #"{"statusLine":{"type":"command","command":"bash -c 'x \"$1\"' -- '\\'","padding":1}}"#)
        let before = try json(original)
        for mode in [TerminalBarMode.wisp, .listen] {
            let installed = try StatusLineChain.install(mode, into: original, helper: helper)
            let switched = try StatusLineChain.install(mode == .wisp ? .listen : .wisp, into: installed, helper: helper)
            XCTAssertEqual(try json(StatusLineChain.restore(from: switched)), before)
        }
    }

    func testRestoreRemovesWispsBarWhenThereWasNone() throws {
        let installed = try StatusLineChain.install(.wisp, into: settings(#"{"model":"opus"}"#), helper: helper)
        XCTAssertEqual(try json(StatusLineChain.restore(from: installed)), .object(["model": .string("opus")]))
    }

    func testAnotherCopysBarIsTakenOverNotWrapped() throws {
        let other = "/Users/me/Wisp Dev.app/Contents/MacOS/wisp-agent"
        let theirs = try StatusLineChain.install(
            .wisp, into: settings(#"{"statusLine":{"command":"mine"}}"#), helper: other)
        let ours = try StatusLineChain.install(.wisp, into: theirs, helper: helper)
        XCTAssertEqual(try StatusLineChain.state(in: ours), .wisp(saved: "mine"))
        XCTAssertTrue(try json(ours)["statusLine"]?["command"]?.stringValue?.hasPrefix("'\(helper)'") ?? false)
    }

    func testForeignCommand() throws {
        XCTAssertEqual(try StatusLineChain.state(in: settings(#"{"statusLine":{"command":"x"}}"#)), .foreign("x"))
        XCTAssertEqual(try StatusLineChain.state(in: settings("")), .none)
    }
}

final class HookInstallerUpdateTests: XCTestCase {
    private let helper = "/Applications/Wisp.app/Contents/MacOS/wisp-agent"

    func testQuoteRoundTrips() {
        for text in ["plain", "it's", "''", "a 'b' c", "", "\\'"] {
            XCTAssertEqual(HookInstaller.unquote(HookInstaller.quote(text)), text)
        }
        XCTAssertNil(HookInstaller.unquote("bare"))
        XCTAssertNil(HookInstaller.unquote("'open"))
    }

    func testClaudeCompactionHooksRunInTheBackground() throws {
        let command = HookInstaller.command(helper: helper, source: .claude)
        let out = try JSONDecoder().decode(
            JSONValue.self, from: HookInstaller.install(into: Data("{}".utf8), command: command, source: .claude))
        XCTAssertEqual(out["hooks"]?["PreCompact"]?[0]?["hooks"]?[0]?["async"], .bool(true))
        XCTAssertEqual(out["hooks"]?["PostCompact"]?[0]?["hooks"]?[0]?["async"], .bool(true))
        XCTAssertNil(out["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["async"])
    }

    func testOlderInstallIsOutdated() throws {
        let command = HookInstaller.command(helper: helper, source: .claude)
        var hooks: [String: JSONValue] = [:]
        for event in ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "SessionEnd"] {
            hooks[event] = .array([
                .object(["matcher": .string(""), "hooks": .array([.object(["command": .string(command)])])])
            ])
        }
        let old = try JSONEncoder().encode(JSONValue.object(["hooks": .object(hooks)]))
        XCTAssertEqual(try HookInstaller.link(in: old, helper: helper, source: .claude), .outdated)
        let updated = try HookInstaller.install(into: old, command: command, source: .claude)
        XCTAssertEqual(try HookInstaller.link(in: updated, helper: helper, source: .claude), .this)
    }
}
