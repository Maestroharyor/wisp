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

    /// Two reports naming the same process confirm it.
    private func confirm(_ sessions: inout AgentSessions, _ session: String, _ process: AgentProcess?) throws {
        sessions.apply(try prompt(session, process: process), at: now)
        sessions.apply(try prompt(session, process: process), at: now)
    }

    func testASessionWhoseAgentExitedEnds() throws {
        var sessions = AgentSessions()
        try confirm(&sessions, "gone", AgentProcess(pid: 1, started: 1))
        try confirm(&sessions, "live", AgentProcess(pid: 2, started: 2))
        try confirm(&sessions, "old", nil)
        let ended = sessions.endExited { $0.pid == 2 }
        XCTAssertEqual(ended, ["gone"])
        XCTAssertEqual(Set(sessions.list.map(\.id)), ["live", "old"])
    }

    /// A short-lived launcher between the agent and the hook has a new pid every time, so it's
    /// never taken for the agent and its exit never ends the session.
    func testAProcessSeenOnceIsNotTrusted() throws {
        var sessions = AgentSessions()
        for pid: Int32 in 10...14 {
            sessions.apply(try prompt("s", process: AgentProcess(pid: pid, started: 1)), at: now)
        }
        XCTAssertNil(sessions.session("s")?.process)
        XCTAssertFalse(sessions.hasProcesses)
        XCTAssertEqual(sessions.endExited { _ in false }, [])
    }

    /// `--resume` brings a new process: the old one no longer counts, and the new one is
    /// trusted once confirmed.
    func testANewProcessReplacesTheOldOnceConfirmed() throws {
        var sessions = AgentSessions()
        let old = AgentProcess(pid: 1, started: 1)
        let new = AgentProcess(pid: 2, started: 2)
        try confirm(&sessions, "s", old)
        sessions.apply(try prompt("s", process: new), at: now)
        XCTAssertNil(sessions.session("s")?.process)
        XCTAssertEqual(sessions.endExited { $0 == new }, [])
        sessions.apply(try prompt("s", process: new), at: now)
        XCTAssertEqual(sessions.session("s")?.process, new)
    }

    func testSnapshotsConfirmTheProcessToo() throws {
        var sessions = AgentSessions()
        var snapshot = StatusLineSnapshot(json: .object(["session_id": .string("s"), "cwd": .string("/p/app")]))
        snapshot.process = AgentProcess(pid: 3, started: 3)
        _ = sessions.apply(snapshot, source: .claude, terminal: nil, branch: nil, at: now)
        XCTAssertNil(sessions.session("s")?.process)
        _ = sessions.apply(snapshot, source: .claude, terminal: nil, branch: nil, at: now)
        XCTAssertEqual(sessions.session("s")?.process, AgentProcess(pid: 3, started: 3))
        XCTAssertTrue(sessions.hasProcesses)
    }
}
