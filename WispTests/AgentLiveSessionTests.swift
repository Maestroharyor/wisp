import XCTest

@testable import WispCore

final class AgentLiveSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ name: String, session: String = "s1") throws -> AgentEvent {
        try AgentEvent.decode(Data(#"{"session_id":"\#(session)","cwd":"/a/wisp","hook_event_name":"\#(name)"}"#.utf8))
    }

    private func snapshot(percent: Double? = 50, cost: Double? = 0.5) -> StatusLineSnapshot {
        StatusLineSnapshot(
            sessionID: "s1", cwd: "/a/wisp", transcriptPath: "/t", model: "Opus", cost: cost, duration: 60,
            apiDuration: 5, linesAdded: 3, linesRemoved: 1, contextPercent: percent, contextSize: 200_000)
    }

    func testSnapshotCreatesAnIdleSessionAndFillsLiveFields() throws {
        var sessions = AgentSessions()
        sessions.apply(snapshot(), source: .claude, terminal: "com.apple.Terminal", branch: "main", at: start)
        let session = try XCTUnwrap(sessions.session("s1"))
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.project, "wisp")
        XCTAssertEqual(session.model, "Opus")
        XCTAssertEqual(session.cost, 0.5)
        XCTAssertTrue(session.costIsReal)
        XCTAssertEqual(session.contextPercent, 50)
        XCTAssertEqual(session.linesAdded, 3)
        XCTAssertEqual(session.branch, "main")
        XCTAssertEqual(session.terminal, "com.apple.Terminal")
    }

    func testSnapshotNeverChangesState() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(snapshot(), source: .claude, terminal: nil, branch: nil, at: start.addingTimeInterval(1))
        XCTAssertEqual(sessions.session("s1")?.state, .running)
    }

    func testSnapshotWithoutSessionIsIgnored() {
        var sessions = AgentSessions()
        sessions.apply(StatusLineSnapshot(cwd: "/a"), source: .claude, terminal: nil, branch: nil, at: start)
        XCTAssertTrue(sessions.list.isEmpty)
    }

    func testEstimateNeverReplacesRealCost() {
        var sessions = AgentSessions()
        sessions.apply(snapshot(cost: 1.25), source: .claude, terminal: nil, branch: nil, at: start)
        sessions.setUsage(TokenUsage(input: 10), cost: 0.9, session: "s1")
        XCTAssertEqual(sessions.session("s1")?.cost, 1.25)
        XCTAssertEqual(sessions.session("s1")?.usage, TokenUsage(input: 10))
    }

    func testCompactionClearsThePercentUntilTheNextFigure() throws {
        var sessions = AgentSessions()
        sessions.apply(snapshot(percent: 92), source: .claude, terminal: nil, branch: nil, at: start)
        sessions.apply(try event("PreCompact"), at: start)
        XCTAssertEqual(sessions.session("s1")?.compacting, true)
        sessions.apply(try event("PostCompact"), at: start)
        XCTAssertEqual(sessions.session("s1")?.compacting, false)
        XCTAssertNil(sessions.session("s1")?.contextPercent)
        XCTAssertEqual(sessions.session("s1")?.timeline.last?.kind, .compacted)
        sessions.apply(snapshot(percent: nil), source: .claude, terminal: nil, branch: nil, at: start)
        XCTAssertNil(sessions.session("s1")?.contextPercent)
        sessions.apply(snapshot(percent: 20), source: .claude, terminal: nil, branch: nil, at: start)
        XCTAssertEqual(sessions.session("s1")?.contextPercent, 20)
    }

    func testPillChangesOnlyForAWorkingSessionAndWholePercents() throws {
        var sessions = AgentSessions()
        XCTAssertFalse(
            sessions.apply(snapshot(percent: 50), source: .claude, terminal: nil, branch: nil, at: start),
            "a session seen first by its snapshot has no pill yet")
        sessions.apply(try event("UserPromptSubmit"), at: start)
        XCTAssertTrue(sessions.apply(snapshot(percent: 51), source: .claude, terminal: nil, branch: nil, at: start))
        XCTAssertFalse(sessions.apply(snapshot(percent: 51.2), source: .claude, terminal: nil, branch: nil, at: start))
        sessions.apply(try event("Stop"), at: start)
        XCTAssertFalse(
            sessions.apply(snapshot(percent: 70), source: .claude, terminal: nil, branch: nil, at: start),
            "Done isn't replayed")
    }

    func testARepeatedSnapshotIsntActivity() throws {
        var sessions = AgentSessions()
        sessions.apply(snapshot(percent: 40), source: .claude, terminal: nil, branch: nil, at: start)
        sessions.apply(
            snapshot(percent: 40), source: .claude, terminal: nil, branch: nil, at: start.addingTimeInterval(60))
        XCTAssertEqual(sessions.session("s1")?.updated, start)
        sessions.apply(
            snapshot(percent: 41), source: .claude, terminal: nil, branch: nil, at: start.addingTimeInterval(90))
        XCTAssertEqual(sessions.session("s1")?.updated, start.addingTimeInterval(90))
    }

    func testCompactingClearsWhenTheTurnMovesOn() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("PreCompact"), at: start)
        XCTAssertEqual(sessions.session("s1")?.compacting, true)
        sessions.apply(try event("UserPromptSubmit"), at: start)
        XCTAssertEqual(sessions.session("s1")?.compacting, false)
        sessions.apply(try event("PreCompact"), at: start)
        sessions.apply(try event("Stop"), at: start)
        XCTAssertEqual(sessions.session("s1")?.compacting, false)
    }

    func testContextAlertFiresOncePerClimb() {
        var sessions = AgentSessions()
        var fired: [Double?] = []
        for percent in [60.0, 82, 88, 30, 81] {
            sessions.apply(snapshot(percent: percent), source: .claude, terminal: nil, branch: nil, at: start)
            fired.append(sessions.contextAlert(session: "s1", threshold: 80))
        }
        XCTAssertEqual(fired, [nil, 82, nil, nil, 81])
    }
}

final class AgentFiguresTests: XCTestCase {
    private func session() -> AgentSession {
        AgentSession(id: "s", project: "p", state: .idle, turnStarted: .now, updated: .now)
    }

    func testEmptyWhenNothingIsKnown() {
        XCTAssertEqual(session().figures, "")
    }

    func testEstimateHasATilde() {
        var estimated = session()
        estimated.usage = TokenUsage(input: 182_000)
        estimated.cost = 0.41
        XCTAssertEqual(estimated.figures, "182k tokens · ~$0.41")
    }

    func testRealCostModelAndDiff() {
        var live = session()
        live.model = "Opus"
        live.cost = 1.5
        live.costIsReal = true
        live.linesAdded = 120
        live.linesRemoved = 34
        XCTAssertEqual(live.figures, "Opus · $1.50 · +120 −34")
    }
}

final class ModelNameTests: XCTestCase {
    func testClaudeIDs() {
        XCTAssertEqual(ModelName.display("claude-opus-4-1-20250805"), "Opus 4.1")
        XCTAssertEqual(ModelName.display("claude-sonnet-5-5"), "Sonnet 5.5")
        XCTAssertEqual(ModelName.display("claude-3-5-sonnet-latest"), "Sonnet 3.5")
        XCTAssertEqual(ModelName.display("claude-opus-5[1m]"), "Opus 5")
        XCTAssertEqual(ModelName.display("claude-fable"), "Fable")
    }

    func testOtherIDsAreUnchanged() {
        XCTAssertEqual(ModelName.display("gpt-5-codex"), "gpt-5-codex")
        XCTAssertEqual(ModelName.display("claude-"), "claude-")
    }
}

final class AgentTurnTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ name: String) throws -> AgentEvent {
        try AgentEvent.decode(Data(#"{"session_id":"s","cwd":"/a/wisp","hook_event_name":"\#(name)"}"#.utf8))
    }

    func testLastTurnDurationAndModelFallback() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        XCTAssertNil(sessions.session("s")?.lastTurnDuration)
        sessions.apply(try event("Stop"), at: start.addingTimeInterval(252))
        XCTAssertEqual(sessions.session("s")?.lastTurnDuration, 252)
        sessions.setModelID("claude-opus-4-1-20250805", session: "s")
        sessions.setBranch("main", session: "s")
        XCTAssertEqual(sessions.session("s")?.displayModel, "Opus 4.1")
        XCTAssertEqual(sessions.session("s")?.branch, "main")
        sessions.apply(try event("UserPromptSubmit"), at: start.addingTimeInterval(300))
        XCTAssertNil(sessions.session("s")?.lastTurnDuration)
    }

    func testATurnSeenOnlyAtItsEndHasNoLength() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("Stop"), at: start)
        XCTAssertEqual(sessions.session("s")?.state, .finished)
        XCTAssertNil(sessions.session("s")?.lastTurnDuration)
    }

    func testTranscriptRemembersTheLatestModel() {
        var usage = TranscriptUsage()
        usage.add(line: #"{"message":{"id":"a","model":"claude-sonnet-5-5","usage":{"input_tokens":1}}}"#)
        usage.add(line: #"{"message":{"id":"b","model":"<synthetic>","usage":{"input_tokens":0}}}"#)
        XCTAssertEqual(usage.lastModel, "claude-sonnet-5-5")
    }
}

final class AgentFactsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testFullSnapshotGivesEveryFact() throws {
        let snapshot = StatusLineSnapshot.decode(
            Data(
                """
                {"session_id":"s","session_name":"agent bar","version":"2.1.300","cwd":"/a/wisp",
                 "model":{"display_name":"Opus"},"effort":{"level":"high"},"thinking":{"enabled":true},"fast_mode":false,
                 "output_style":{"name":"Explanatory"},
                 "cost":{"total_cost_usd":1.5,"total_duration_ms":3780000,"total_api_duration_ms":252000,
                         "total_lines_added":12,"total_lines_removed":3},
                 "context_window":{"used_percentage":78,"context_window_size":200000,"total_input_tokens":500000,
                                   "total_output_tokens":20000,
                                   "current_usage":{"input_tokens":1000,"cache_read_input_tokens":150000,
                                                    "cache_creation_input_tokens":5000,"output_tokens":10}},
                 "rate_limits":{"five_hour":{"used_percentage":41.6},"seven_day":{"used_percentage":12}},
                 "prompt_cache":{"hit_ratio":0.93},"pr":{"number":12,"review_state":"changes_requested"},
                 "worktree":{"branch":"feat/x"}}
                """.utf8))
        var sessions = AgentSessions()
        sessions.apply(snapshot, source: .claude, terminal: nil, branch: nil, at: now)
        let facts = try XCTUnwrap(sessions.session("s")).facts(now: now.addingTimeInterval(90))
        let byLabel = Dictionary(uniqueKeysWithValues: facts.map { ($0.label, $0.value) })
        XCTAssertEqual(byLabel["Name"], "agent bar")
        XCTAssertEqual(byLabel["Model"], "Opus · high effort · thinking")
        XCTAssertEqual(byLabel["Context"], "78% · 156k of 200k")
        XCTAssertEqual(byLabel["Cost"], "$1.50")
        XCTAssertEqual(byLabel["Tokens"], "500k in · 20k out")
        XCTAssertEqual(byLabel["Lines"], "+12 −3")
        XCTAssertEqual(byLabel["Duration"], "1h 03m · 4m 12s waiting on the model")
        XCTAssertEqual(byLabel["Branch"], "feat/x · PR #12 (changes requested)")
        XCTAssertEqual(byLabel["Cache hits"], "93%")
        XCTAssertEqual(byLabel["Usage limits"], "42% of 5 h · 12% of 7 days")
        XCTAssertEqual(byLabel["Output style"], "Explanatory")
        XCTAssertEqual(byLabel["Agent"], "Claude Code 2.1.300")
        XCTAssertEqual(byLabel["Last activity"], "1m 30s ago")
        XCTAssertEqual(byLabel["Session ID"], "s")
    }

    func testHookOnlySessionShowsWhatItHas() {
        var session = AgentSession(id: "s", project: "p", state: .finished, turnStarted: now, updated: now)
        session.usage = TokenUsage(input: 1000, output: 2000, cacheWrite: 3000, cacheRead: 4000)
        session.cost = 0.5
        session.modelID = "claude-sonnet-5-5"
        let labels = session.facts(now: now).map(\.label)
        XCTAssertEqual(labels, ["Model", "Cost", "Tokens", "Agent", "Last activity", "Session ID"])
        XCTAssertEqual(session.facts(now: now)[2].value, "1k in · 2k out · 4k cache read · 3k cache write")
    }
}
