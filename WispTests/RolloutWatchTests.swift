import XCTest

@testable import WispCore

final class RolloutWatchTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ kind: String, source: String = "codex", transcript: Bool = true) throws -> AgentEvent {
        let path = transcript ? #","transcript_path":"/r/rollout.jsonl""# : ""
        return try AgentEvent.decode(
            Data(#"{"session_id":"s","cwd":"/w","wisp_source":"\#(source)","hook_event_name":"\#(kind)"\#(path)}"#.utf8)
        )
    }

    // MARK: When to watch

    func testCodexTurnActivityStartsTheWatch() throws {
        for kind in ["UserPromptSubmit", "PermissionRequest"] {
            XCTAssertTrue(RolloutWatch.starts(try event(kind), running: false), kind)
        }
        for kind in ["PreToolUse", "PostToolUse"] {
            XCTAssertTrue(RolloutWatch.starts(try event(kind), running: true), kind)
        }
        XCTAssertFalse(RolloutWatch.starts(try event("SessionStart"), running: true))
    }

    func testALateToolEventAfterTheTurnDoesNotStartIt() throws {
        XCTAssertFalse(RolloutWatch.starts(try event("PostToolUse"), running: false))
    }

    func testOnlyCodexWithATranscriptIsWatched() throws {
        XCTAssertFalse(RolloutWatch.starts(try event("UserPromptSubmit", source: "claude"), running: true))
        XCTAssertFalse(RolloutWatch.starts(try event("UserPromptSubmit", transcript: false), running: true))
    }

    func testTheEndOfATurnStopsIt() throws {
        for kind in ["Stop", "SessionEnd", "Interrupt"] {
            XCTAssertTrue(RolloutWatch.stops(try event(kind)), kind)
        }
        XCTAssertFalse(RolloutWatch.stops(try event("PostToolUse")))
    }

    // MARK: Throttle

    func testFirstChangeReadsAtOnceThenOncePerInterval() {
        var throttle = ReadThrottle(interval: 1)
        XCTAssertEqual(throttle.request(now: start), 0)
        // Already scheduled: the same read covers it.
        XCTAssertNil(throttle.request(now: start.addingTimeInterval(0.1)))
        throttle.didRead(now: start.addingTimeInterval(0.1))
        XCTAssertEqual(try XCTUnwrap(throttle.request(now: start.addingTimeInterval(0.4))), 0.7, accuracy: 1e-6)
        XCTAssertNil(throttle.request(now: start.addingTimeInterval(0.5)))
        throttle.didRead(now: start.addingTimeInterval(1.1))
        XCTAssertEqual(throttle.request(now: start.addingTimeInterval(3)), 0)
    }

    // MARK: Reading complete lines

    func testReadsCompleteLinesAndLeavesAPartialOneForNextTime() {
        let first =
            #"{"timestamp":"2026-11-14T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10,"total_tokens":110},"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10,"total_tokens":25840},"model_context_window":258400},"rate_limits":null}}"#
        let partial = #"{"timestamp":"2026-11-14T10:00:01.000Z","type":"event_msg","payload":{"type":"tok"#
        var usage = TranscriptUsage()
        let used = usage.add(complete: Data((first + "\n" + partial).utf8))
        XCTAssertEqual(used, first.utf8.count + 1)
        XCTAssertEqual(try XCTUnwrap(usage.contextPercent), 10, accuracy: 1e-9)
        XCTAssertEqual(usage.add(complete: Data(partial.utf8)), 0)
    }

    func testANullInfoKeepsTheLastContext() throws {
        let full =
            #"{"timestamp":"2026-11-14T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":110},"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":129200},"last_usage_includes_reasoning":false,"model_context_window":258400},"rate_limits":null}}"#
        let empty =
            #"{"timestamp":"2025-01-03T12:00:00.000Z","ordinal":7,"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":null,"limit_name":null,"primary":{"used_percent":0.0,"window_minutes":60,"resets_at":1800000000},"secondary":{"used_percent":12.5,"window_minutes":10080,"resets_at":1800100000},"credits":null}}}"#
        var usage = TranscriptUsage()
        usage.add(lines: [full, empty])
        XCTAssertEqual(try XCTUnwrap(usage.contextPercent), 50, accuracy: 1e-9)
        XCTAssertEqual(usage.total.input, 100)
    }
}
