import XCTest

@testable import WispCore

final class SessionRecorderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ kind: String, source: String = "claude", extra: String = "") throws -> AgentEvent {
        try AgentEvent.decode(
            Data(
                #"{"session_id":"s","cwd":"/p/app","wisp_source":"\#(source)","hook_event_name":"\#(kind)"\#(extra)}"#
                    .utf8))
    }

    private func bash(_ kind: String, _ command: String, id: String, source: String = "claude") throws -> AgentEvent {
        try event(
            kind, source: source,
            extra: #","tool_name":"Bash","tool_use_id":"\#(id)","tool_input":{"command":"\#(command)"}"#)
    }

    private func edit(_ path: String, id: String) throws -> AgentEvent {
        try event(
            "PreToolUse", extra: #","tool_name":"Edit","tool_use_id":"\#(id)","tool_input":{"file_path":"\#(path)"}"#)
    }

    /// Feeds the events to both the live sessions and the recorder, as the hub does.
    private func run(
        _ events: [AgentEvent], keepDetails: Bool = true, recorder: inout SessionRecorder,
        sessions: inout AgentSessions
    ) {
        for (offset, event) in events.enumerated() {
            let date = start.addingTimeInterval(Double(offset) * 10)
            recorder.observe(event, at: date, keepDetails: keepDetails, session: sessions.session(event.sessionID))
            sessions.apply(event, at: date)
        }
    }

    func testARecordCollectsToolsFilesCommandsAndTests() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run(
            [
                try event("SessionStart"), try event("UserPromptSubmit", extra: #","prompt":"secret plan""#),
                try edit("/p/app/Sources/Hub.swift", id: "e1"), try edit("/p/app/Sources/Hub.swift", id: "e2"),
                try edit("/etc/hosts", id: "e3"),
                try bash("PreToolUse", "GITHUB_TOKEN=abc123 make test", id: "t1"),
                try bash("PostToolUse", "GITHUB_TOKEN=abc123 make test", id: "t1"),
                try bash("PreToolUse", "swift test", id: "t2"),
                try event("PermissionRequest", extra: #","tool_name":"Bash""#), try event("Stop"),
            ], recorder: &recorder, sessions: &sessions)
        let session = try XCTUnwrap(sessions.session("s"))
        let record = try XCTUnwrap(recorder.record(session, at: start.addingTimeInterval(100)))
        XCTAssertEqual(record.project, "app")
        XCTAssertEqual(record.turns, 1)
        XCTAssertEqual(record.tools, ["Edit": 3, "Bash": 2])
        XCTAssertEqual(record.files, ["Sources/Hub.swift", "hosts"])
        XCTAssertEqual(record.commands, ["GITHUB_TOKEN=••• make test", "swift test"])
        XCTAssertEqual(
            record.tests,
            [
                TestRun(command: "GITHUB_TOKEN=••• make test", outcome: .passed),
                TestRun(command: "swift test", outcome: .notPassed),
            ])
        XCTAssertEqual(record.requests, 1)
        XCTAssertEqual(record.started, start)
        XCTAssertEqual(record.duration, 100)
        XCTAssertFalse(record.endedWaiting)
        // The prompt is never part of a record.
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertFalse(encoded.contains("secret plan"))
        XCTAssertFalse(encoded.contains("abc123"))
    }

    func testHiddenDetailsAreNeverStored() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run(
            [
                try event("UserPromptSubmit"), try edit("/p/app/a.swift", id: "e1"),
                try bash("PreToolUse", "npm test", id: "t1"), try bash("PostToolUse", "npm test", id: "t1"),
            ], keepDetails: false, recorder: &recorder, sessions: &sessions)
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(record.files, [])
        XCTAssertEqual(record.commands, [])
        XCTAssertEqual(record.tests, [TestRun(command: "Tests", outcome: .passed)])
        XCTAssertEqual(record.tools, ["Edit": 1, "Bash": 1])
    }

    func testOtherAgentsTestsOnlyCountAsRan() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run(
            [
                try bash("PreToolUse", "cargo test", id: "t1", source: "copilot"),
                try bash("PostToolUse", "cargo test", id: "t1", source: "copilot"),
                try bash("PreToolUse", "go test ./...", id: "t2", source: "copilot"),
                try event("Stop", source: "copilot"),
            ], recorder: &recorder, sessions: &sessions)
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(record.tests.map(\.outcome), [.ran, .ran])
    }

    func testADeniedTestIsNotAFailure() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run(
            [try bash("PreToolUse", "pytest", id: "t1"), try bash("PreToolUse", "cargo test", id: "t2")],
            recorder: &recorder, sessions: &sessions)
        recorder.denied(session: "s", command: "pytest")
        recorder.denied(session: "s", command: "ls")
        run([try event("Stop")], recorder: &recorder, sessions: &sessions)
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(record.tests, [TestRun(command: "cargo test", outcome: .notPassed)])
    }

    func testAResumeStartsANewRecord() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run([try event("UserPromptSubmit"), try event("Stop")], recorder: &recorder, sessions: &sessions)
        let first = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        let resume = try event("SessionStart", extra: #","source":"resume""#)
        recorder.observe(resume, at: start.addingTimeInterval(500), keepDetails: true, session: sessions.session("s"))
        sessions.apply(resume, at: start.addingTimeInterval(500))
        let second = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.turns, 0)
    }

    func testACompactionKeepsTheRun() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run(
            [
                try event("UserPromptSubmit"), try edit("/p/app/a.swift", id: "e1"),
                try event("SessionStart", extra: #","source":"compact""#), try event("UserPromptSubmit"),
                try event("Stop"),
            ], recorder: &recorder, sessions: &sessions)
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(record.started, start)
        XCTAssertEqual(record.turns, 2)
        XCTAssertEqual(record.files, ["a.swift"])
    }

    func testFiguresAreCountedFromTheRunsStart() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run([try event("UserPromptSubmit")], recorder: &recorder, sessions: &sessions)
        sessions.setUsage(TokenUsage(input: 1000), cost: 1.0, session: "s")
        run(
            [try event("Stop"), try event("SessionStart", extra: #","source":"resume""#)], recorder: &recorder,
            sessions: &sessions)
        sessions.setUsage(TokenUsage(input: 1500), cost: 1.5, session: "s")
        recorder.figuresChanged(try XCTUnwrap(sessions.session("s")))
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(try XCTUnwrap(record.cost), 0.5, accuracy: 0.0001)
        XCTAssertEqual(record.tokens, 500)
    }

    /// A resumed agent counts from zero while Wisp's session still holds the old figure; once the
    /// new count passes the old one it must not be read as a small increase.
    func testACounterThatStartedOverIsCountedInFullAfterItPassesTheOldFigure() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run([try event("UserPromptSubmit")], recorder: &recorder, sessions: &sessions)
        sessions.setUsage(TokenUsage(input: 5000), cost: 5.0, session: "s")
        run(
            [try event("Stop"), try event("SessionStart", extra: #","source":"resume""#)], recorder: &recorder,
            sessions: &sessions)
        sessions.setUsage(TokenUsage(input: 100), cost: 1.0, session: "s")
        recorder.figuresChanged(try XCTUnwrap(sessions.session("s")))
        sessions.setUsage(TokenUsage(input: 7000), cost: 7.0, session: "s")
        recorder.figuresChanged(try XCTUnwrap(sessions.session("s")))
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(try XCTUnwrap(record.cost), 7.0, accuracy: 0.0001)
        XCTAssertEqual(record.tokens, 7000)
    }

    func testAnExitedSessionsOpenTestsAreUnknown() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run([try bash("PreToolUse", "make test", id: "t1")], recorder: &recorder, sessions: &sessions)
        recorder.exited(session: "s")
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(record.tests, [TestRun(command: "make test", outcome: .unknown)])
    }

    func testCopilotPostToolUseAloneIsCountedOnce() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        // Tool activity off: only the always-installed PostToolUse arrives.
        run(
            [try bash("PostToolUse", "npm test", id: "t1", source: "copilot")], recorder: &recorder,
            sessions: &sessions)
        // Tool activity on: PreToolUse then PostToolUse for the same call.
        run(
            [
                try bash("PreToolUse", "ls", id: "t2", source: "copilot"),
                try bash("PostToolUse", "ls", id: "t2", source: "copilot"),
            ], recorder: &recorder, sessions: &sessions)
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(record.tools, ["Bash": 2])
        XCTAssertEqual(record.commands, ["npm test", "ls"])
        XCTAssertEqual(record.tests, [TestRun(command: "npm test", outcome: .ran)])
    }

    func testATestWaitingOnPermissionIsNotAFailure() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run(
            [
                try bash("PreToolUse", "pytest", id: "t1"),
                try event("PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"pytest"}"#),
                try event("Stop"),
            ], recorder: &recorder, sessions: &sessions)
        let record = try XCTUnwrap(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
        XCTAssertEqual(record.tests, [TestRun(command: "pytest", outcome: .unknown)])
    }

    func testRecordsNeedAStart() throws {
        let recorder = SessionRecorder()
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        XCTAssertNil(recorder.record(try XCTUnwrap(sessions.session("s")), at: start))
    }

    func testForgettingAndKeeping() throws {
        var recorder = SessionRecorder()
        var sessions = AgentSessions()
        run([try event("UserPromptSubmit")], recorder: &recorder, sessions: &sessions)
        let session = try XCTUnwrap(sessions.session("s"))
        recorder.keep(only: ["s"])
        XCTAssertNotNil(recorder.record(session, at: start))
        recorder.keep(only: [])
        XCTAssertNil(recorder.record(session, at: start))
    }

    func testTestCommands() {
        for command in [
            "make test", "swift test --filter X", "npm test", "npm run test:unit", "pnpm test", "yarn test",
            "bun test", "npx vitest run", "pytest -q", "python -m pytest", "cargo test", "go test ./...",
            "xcodebuild -scheme Wisp test", "cd app && make test", "./gradlew test", "bundle exec rspec",
            "make -j4 test",
        ] {
            XCTAssertTrue(TestCommand.isTest(command), command)
        }
        for command in ["make build", "git status", "echo testing", "cat test.txt", "make build && echo test"] {
            XCTAssertFalse(TestCommand.isTest(command), command)
        }
    }

    func testCommandsAreCutToOneLine() {
        XCTAssertEqual(SessionRecorder.clean("git add .\ngit commit"), "git add .")
        let long = SessionRecorder.clean(String(repeating: "a", count: 300))
        XCTAssertEqual(long.count, SessionRecorder.commandLength)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}

final class SessionHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ session: String, ended: TimeInterval, project: String = "app") -> SessionRecord {
        SessionRecord(
            sessionID: session, project: project, source: .claude, started: now.addingTimeInterval(ended - 60),
            ended: now.addingTimeInterval(ended), turns: 1)
    }

    func testSaveReplacesKeepsSummaryAndSortsNewestFirst() {
        var history = SessionHistory()
        history.save(record("a", ended: -100), now: now)
        history.save(record("b", ended: -50), now: now)
        history.setSummary("Fixed it.", for: record("a", ended: -100).id)
        var updated = record("a", ended: -100)
        updated.ended = now
        updated.turns = 3
        history.save(updated, now: now)
        XCTAssertEqual(history.records.map(\.sessionID), ["a", "b"])
        XCTAssertEqual(history.records.first?.turns, 3)
        XCTAssertEqual(history.records.first?.summary, "Fixed it.")
    }

    func testCapsByCountAndAge() {
        var history = SessionHistory()
        for index in 0..<(SessionHistory.limit + 5) {
            history.save(record("s\(index)", ended: -Double(index)), now: now)
        }
        XCTAssertEqual(history.records.count, SessionHistory.limit)
        XCTAssertEqual(history.records.first?.sessionID, "s0")
        history.save(record("old", ended: -SessionHistory.maxAge - 1), now: now)
        XCTAssertFalse(history.records.contains { $0.sessionID == "old" })
        history.prune(now: now.addingTimeInterval(SessionHistory.maxAge + 1000))
        XCTAssertTrue(history.records.isEmpty)
    }

    func testRemoveAndClear() {
        var history = SessionHistory()
        history.save(record("a", ended: 0), now: now)
        history.save(record("b", ended: 0), now: now)
        history.remove(record("a", ended: 0).id)
        XCTAssertEqual(history.records.map(\.sessionID), ["b"])
        history.clear()
        XCTAssertTrue(history.records.isEmpty)
    }

    func testRoundTripsThroughJSON() throws {
        var history = SessionHistory()
        var full = record("a", ended: 0)
        full.tools = ["Bash": 2]
        full.tests = [TestRun(command: "make test", outcome: .passed)]
        full.cost = 0.42
        history.save(full, now: now)
        let decoded = try JSONDecoder().decode(SessionHistory.self, from: try JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
    }

    func testDecodeSkipsBadRecordsAndWritesAVersion() throws {
        var history = SessionHistory()
        history.save(record("a", ended: 0), now: now)
        let encoded = String(decoding: try JSONEncoder().encode(history), as: UTF8.self)
        XCTAssertTrue(encoded.contains(#""version":1"#))
        // A second record with a field missing is skipped; the good one survives.
        let broken = encoded.replacingOccurrences(of: #""records":["#, with: #""records":[{"id":"x"},"#)
        let decoded = try SessionHistory.decode(Data(broken.utf8), now: now)
        XCTAssertEqual(decoded.records.map(\.sessionID), ["a"])
        XCTAssertThrowsError(try SessionHistory.decode(Data("not json".utf8), now: now))
        XCTAssertThrowsError(try SessionHistory.decode(Data(#"{"version":1}"#.utf8), now: now))
    }

    func testDecodePrunesOldRecords() throws {
        let history = SessionHistory(records: [record("old", ended: -SessionHistory.maxAge - 1), record("a", ended: 0)])
        let decoded = try SessionHistory.decode(try JSONEncoder().encode(history), now: now)
        XCTAssertEqual(decoded.records.map(\.sessionID), ["a"])
    }

    func testOnlyNewerWritesGetThrough() {
        var gate = WriteGate()
        XCTAssertFalse(gate.admit(0))
        XCTAssertTrue(gate.admit(3))
        XCTAssertFalse(gate.admit(2))
        XCTAssertFalse(gate.admit(3))
        XCTAssertTrue(gate.admit(4))
        XCTAssertEqual(gate.latest, 4)
    }

    func testSearchSkipsHiddenFields() {
        var history = SessionHistory()
        var one = record("a", ended: 0, project: "wisp")
        one.files = ["Sources/Login.swift"]
        one.summary = "Fixed the login bug."
        one.branch = "fix/login"
        history.save(one, now: now)
        history.save(record("b", ended: -1, project: "site"), now: now)
        XCTAssertEqual(history.search("", hidden: false).count, 2)
        XCTAssertEqual(history.search("WISP", hidden: true).map(\.sessionID), ["a"])
        XCTAssertEqual(history.search("login.swift", hidden: false).map(\.sessionID), ["a"])
        XCTAssertEqual(history.search("login.swift", hidden: true), [])
        XCTAssertEqual(history.search("claude site", hidden: true).map(\.sessionID), ["b"])
        XCTAssertEqual(history.search("fix/login", hidden: true).map(\.sessionID), ["a"])
    }

    func testEmptyRecords() {
        var empty = record("a", ended: 0)
        empty.turns = 0
        XCTAssertTrue(empty.isEmpty)
        empty.cost = 0.01
        XCTAssertFalse(empty.isEmpty)
    }

    func testSummaryInputHasFactsOnly() {
        var full = record("a", ended: 0)
        full.branch = "main"
        full.model = "Opus"
        full.duration = 125
        full.cost = 0.41
        full.linesAdded = 12
        full.linesRemoved = 3
        full.tools = ["Edit": 2, "Bash": 5]
        full.files = ["a.swift"]
        full.commands = ["make test"]
        full.tests = [TestRun(command: "make test", outcome: .notPassed)]
        full.questions = 1
        full.endedWaiting = true
        let shown = full.summaryInput(hidden: false)
        XCTAssertEqual(
            shown,
            """
            Project: app (branch main)
            Agent: Claude Code, model Opus
            Length: 2m 5s, 1 prompt
            Cost: ~$0.41
            Lines changed: +12 -3
            Tool calls: Bash 5, Edit 2
            Files changed: a.swift
            Commands run: make test
            Tests: make test failed or stopped
            Questions asked: 1
            Waiting for the user at the end: yes
            """)
        let hidden = full.summaryInput(hidden: true)
        XCTAssertFalse(hidden.contains("a.swift"))
        XCTAssertFalse(hidden.contains("make test"))
        XCTAssertTrue(hidden.contains("Tests: Tests failed or stopped"))
    }
}

final class SessionSummaryTextTests: XCTestCase {
    func testFirstSentence() {
        XCTAssertEqual(SessionSummaryText.firstSentence("Fixed the bug. Tests pass."), "Fixed the bug.")
        XCTAssertEqual(SessionSummaryText.firstSentence("  Added v1.2 notes\nMore"), "Added v1.2 notes")
        XCTAssertEqual(SessionSummaryText.firstSentence(""), "")
        let long = SessionSummaryText.firstSentence(String(repeating: "word ", count: 60))
        XCTAssertEqual(long.count, SessionSummaryText.noticeLimit)
    }

    func testNoticeIsHiddenWithDetails() {
        XCTAssertEqual(
            SessionSummaryText.notice(project: "wisp", summary: "Fixed login. Done.", hidden: false),
            "wisp: Fixed login.")
        XCTAssertNil(SessionSummaryText.notice(project: "wisp", summary: "Fixed login.", hidden: true))
        XCTAssertNil(SessionSummaryText.notice(project: "wisp", summary: nil, hidden: false))
        XCTAssertNil(SessionSummaryText.notice(project: "wisp", summary: "  ", hidden: false))
    }

    func testDonePushCarriesTheSummaryOnlyWithDetails() {
        let done = AgentMoment.done(session: "s", project: "wisp", source: .claude, summary: "Fixed login. More.")
        XCTAssertEqual(done.notice(hidden: false).message, "Claude Code finished in wisp.")
        XCTAssertEqual(
            done.notice(hidden: false, includeDetails: true).message, "Claude Code finished in wisp. Fixed login.")
        XCTAssertEqual(done.notice(hidden: true, includeDetails: true).message, "Claude Code finished.")
        XCTAssertEqual(done.key, "s")
    }

    func testDoneWaitsForTheSummaryOnlyWhenItCanGoOut() {
        XCTAssertTrue(DonePush.waitsForSummary(pushOn: true, doneOn: true, includeDetails: true, hidden: false))
        XCTAssertFalse(DonePush.waitsForSummary(pushOn: false, doneOn: true, includeDetails: true, hidden: false))
        XCTAssertFalse(DonePush.waitsForSummary(pushOn: true, doneOn: false, includeDetails: true, hidden: false))
        XCTAssertFalse(DonePush.waitsForSummary(pushOn: true, doneOn: true, includeDetails: false, hidden: false))
        XCTAssertFalse(DonePush.waitsForSummary(pushOn: true, doneOn: true, includeDetails: true, hidden: true))
    }

    func testSettingsSearchFindsHistory() {
        XCTAssertTrue(SettingsIndex.panes(matching: "session history").contains(.agents))
        XCTAssertTrue(SettingsIndex.panes(matching: "summaries").contains(.agents))
    }
}
