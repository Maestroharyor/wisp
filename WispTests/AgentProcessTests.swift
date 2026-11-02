import XCTest

@testable import WispCore

final class AgentProcessTests: XCTestCase {
    private typealias Info = AgentProcess.Info

    /// helper 50 ← sh 40 ← claude 30 ← zsh 20 ← launchd 1
    private let table: [Int32: Info] = [
        40: Info(parent: 30, name: "sh", started: 4),
        30: Info(parent: 20, name: "claude", started: 3),
        20: Info(parent: 1, name: "-zsh", started: 2),
        1: Info(parent: 0, name: "launchd", started: 1),
    ]

    func testTheOwnerSkipsTheShellThatRanTheHook() {
        XCTAssertEqual(AgentProcess.owner(from: 40) { self.table[$0] }, AgentProcess(pid: 30, started: 3))
    }

    func testARunWithoutAShellIsItsOwnParent() {
        XCTAssertEqual(AgentProcess.owner(from: 30) { self.table[$0] }, AgentProcess(pid: 30, started: 3))
    }

    func testOnlyShellsUpToLaunchdMeansNoOwner() {
        let shells: [Int32: Info] = [
            40: Info(parent: 20, name: "bash", started: 4), 20: Info(parent: 1, name: "-zsh", started: 2),
        ]
        XCTAssertNil(AgentProcess.owner(from: 40) { shells[$0] })
    }

    func testAFailedLookupMeansNoOwner() {
        XCTAssertNil(AgentProcess.owner(from: 99) { self.table[$0] })
    }

    func testTheWalkStopsOnALoop() {
        let loop: [Int32: Info] = [
            40: Info(parent: 41, name: "sh", started: 4), 41: Info(parent: 40, name: "sh", started: 5),
        ]
        XCTAssertNil(AgentProcess.owner(from: 40) { loop[$0] })
    }

    func testRunningMeansTheSamePidAndStartTime() {
        let process = AgentProcess(pid: 30, started: 3)
        XCTAssertTrue(process.isRunning { self.table[$0] })
        // The pid was reused by a later process.
        XCTAssertFalse(process.isRunning { _ in Info(parent: 1, name: "claude", started: 9) })
        XCTAssertFalse(process.isRunning { _ in nil })
    }

    /// This test process is alive, and its parent's start time is read the same way twice.
    func testTheSystemTableFindsThisProcess() throws {
        let me = try XCTUnwrap(AgentProcess.systemInfo(getpid()))
        XCTAssertEqual(me.parent, getppid())
        let process = AgentProcess(pid: getpid(), started: me.started)
        XCTAssertTrue(process.isRunning(info: AgentProcess.systemInfo))
        XCTAssertNil(AgentProcess.systemInfo(-5))
    }
}

final class AgentProcessProtocolTests: XCTestCase {
    private let payload = Data(#"{"session_id":"s","cwd":"/p/app","hook_event_name":"Stop"}"#.utf8)

    func testTheEnvelopeCarriesTheProcess() throws {
        let process = AgentProcess(pid: 4242, started: 1_790_000_000.25)
        let data = try XCTUnwrap(
            AgentProtocol.envelope(kind: .hook, source: .claude, terminal: nil, process: process, payload: payload))
        guard case .hook(let event) = try AgentProtocol.decode(data) else { return XCTFail("not a hook") }
        XCTAssertEqual(event.process, process)
    }

    func testAnEnvelopeWithoutAProcessStillDecodes() throws {
        let data = try XCTUnwrap(AgentProtocol.envelope(kind: .hook, source: .claude, terminal: nil, payload: payload))
        guard case .hook(let event) = try AgentProtocol.decode(data) else { return XCTFail("not a hook") }
        XCTAssertNil(event.process)
    }

    func testASnapshotCarriesTheProcess() throws {
        let process = AgentProcess(pid: 7, started: 1)
        let snapshot = Data(#"{"session_id":"s","cwd":"/p/app"}"#.utf8)
        let data = try XCTUnwrap(
            AgentProtocol.envelope(
                kind: .statusline, source: .claude, terminal: nil, process: process, payload: snapshot)
        )
        guard case .statusline(let decoded, _, _) = try AgentProtocol.decode(data) else { return XCTFail() }
        XCTAssertEqual(decoded.process, process)
    }
}

final class AgentExitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func prompt(_ session: String, process: AgentProcess?) throws -> AgentEvent {
        var event = try AgentEvent.decode(
            Data(#"{"session_id":"\#(session)","cwd":"/p/app","hook_event_name":"UserPromptSubmit"}"#.utf8))
        event.process = process
        return event
    }

    func testASessionWhoseAgentExitedEnds() throws {
        var sessions = AgentSessions()
        sessions.apply(try prompt("gone", process: AgentProcess(pid: 1, started: 1)), at: now)
        sessions.apply(try prompt("live", process: AgentProcess(pid: 2, started: 2)), at: now)
        sessions.apply(try prompt("old", process: nil), at: now)
        let ended = sessions.endExited { $0.pid == 2 }
        XCTAssertEqual(ended, ["gone"])
        XCTAssertEqual(Set(sessions.list.map(\.id)), ["live", "old"])
    }

    func testASnapshotSetsTheProcess() throws {
        var sessions = AgentSessions()
        var snapshot = StatusLineSnapshot(json: .object(["session_id": .string("s"), "cwd": .string("/p/app")]))
        snapshot.process = AgentProcess(pid: 3, started: 3)
        _ = sessions.apply(snapshot, source: .claude, terminal: nil, branch: nil, at: now)
        XCTAssertEqual(sessions.session("s")?.process, AgentProcess(pid: 3, started: 3))
        XCTAssertTrue(sessions.hasProcesses)
    }
}
