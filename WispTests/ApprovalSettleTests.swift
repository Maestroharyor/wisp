import XCTest

@testable import WispCore

final class ApprovalSettleTests: XCTestCase {
    private func event(_ json: String, source: AgentSource = .claude) throws -> AgentEvent {
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(source.adapter.parse(payload, terminal: nil))
    }

    private func request(_ id: Int, _ json: String, source: AgentSource = .claude) throws
        -> ApprovalSettle.Request<Int>
    {
        ApprovalSettle.Request(id: id, event: try event(json, source: source))
    }

    private let bash =
        #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#

    func testTheSameCallFinishingSettlesItsRequest() throws {
        let pending = [try request(1, bash)]
        let ran = try event(
            #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(ApprovalSettle.settled(pending, by: ran), [1])
    }

    func testAnotherCallOrSessionLeavesItAlone() throws {
        let pending = [try request(1, bash)]
        // A parallel call to the same tool with another command.
        let other = try event(
            #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"pwd"}}"#)
        XCTAssertEqual(ApprovalSettle.settled(pending, by: other), [])
        let otherTool = try event(
            #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(ApprovalSettle.settled(pending, by: otherTool), [])
        let otherSession = try event(
            #"{"session_id":"t","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(ApprovalSettle.settled(pending, by: otherSession), [])
    }

    func testPreToolUseNeverSettles() throws {
        // Tool hooks run in the background, so a call's own PreToolUse can land after its request.
        let pending = [try request(1, bash)]
        let starting = try event(
            #"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(ApprovalSettle.settled(pending, by: starting), [])
    }

    func testASubagentsCallDoesntSettleTheMainAgentsRequest() throws {
        let pending = [try request(1, bash)]
        let subagent = try event(
            #"{"session_id":"s","agent_id":"a1","hook_event_name":"PostToolUse","tool_name":"Bash","#
                + #""tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(ApprovalSettle.settled(pending, by: subagent), [])
        let fromSubagent = try request(
            2,
            #"{"session_id":"s","agent_id":"a1","hook_event_name":"PermissionRequest","tool_name":"Bash","#
                + #""tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(ApprovalSettle.settled([fromSubagent], by: subagent), [2])
    }

    func testAQuestionSettlesWhenItsToolRanWhateverTheAnswer() throws {
        let question = try request(
            1,
            #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","#
                + #""tool_input":{"questions":[{"question":"Push?"}]}}"#)
        // The answers come back inside the input, so it isn't compared.
        let answered = try event(
            #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","#
                + #""tool_input":{"questions":[{"question":"Push?"}],"answers":{"Push?":"Yes"}}}"#)
        XCTAssertEqual(ApprovalSettle.settled([question], by: answered), [1])
    }

    func testCodexInterruptSettlesEveryRequestInItsSession() throws {
        let pending = [
            try request(1, bash, source: .codex),
            try request(
                2,
                #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"apply_patch","#
                    + #""tool_input":{"command":"*** Begin Patch"}}"#, source: .codex),
            try request(
                3, #"{"session_id":"t","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#, source: .codex),
        ]
        let interrupt = try event(
            #"{"session_id":"s","hook_event_name":"Interrupt","turn_id":"x"}"#, source: .codex)
        XCTAssertEqual(interrupt.kind, .interrupt)
        XCTAssertEqual(ApprovalSettle.settled(pending, by: interrupt), [1, 2])
    }

    func testAFinishedTranscriptCallSettlesTheSameMainAgentRequest() throws {
        let pending = [
            try request(1, bash),
            try request(
                2,
                #"{"session_id":"s","agent_id":"a1","hook_event_name":"PermissionRequest","tool_name":"Bash","#
                    + #""tool_input":{"command":"ls"}}"#),
            try request(3, bash.replacingOccurrences(of: #""session_id":"s""#, with: #""session_id":"t""#)),
        ]
        let ls = TranscriptCalls.Call(tool: "Bash", input: .object(["command": .string("ls")]))
        // The transcript is the main agent's, so a subagent's request and other sessions stay.
        XCTAssertEqual(ApprovalSettle.settled(pending, finished: ls, session: "s"), [1])
        let pwd = TranscriptCalls.Call(tool: "Bash", input: .object(["command": .string("pwd")]))
        XCTAssertEqual(ApprovalSettle.settled(pending, finished: pwd, session: "s"), [])
    }

    func testATranscriptCallMatchesARequestClaudeCodeFilledOut() throws {
        let filled = try request(
            1,
            #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","#
                + #""tool_input":{"command":"ls","timeout":120000}}"#)
        let ls = TranscriptCalls.Call(tool: "Bash", input: .object(["command": .string("ls")]))
        XCTAssertEqual(ApprovalSettle.settled([filled], finished: ls, session: "s"), [1])
        // A call with a field the request lacks, or another value, is another call.
        let more = TranscriptCalls.Call(
            tool: "Bash", input: .object(["command": .string("ls"), "run_in_background": .bool(true)]))
        XCTAssertEqual(ApprovalSettle.settled([try request(2, bash)], finished: more, session: "s"), [])
    }

    func testAFinishedTranscriptQuestionSettlesWhateverTheAnswer() throws {
        let question = try request(
            1,
            #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","#
                + #""tool_input":{"questions":[{"question":"Push?"}]}}"#)
        let answered = TranscriptCalls.Call(tool: "AskUserQuestion", input: .object(["questions": .array([])]))
        XCTAssertEqual(ApprovalSettle.settled([question], finished: answered, session: "s"), [1])
    }

    func testOtherEventsSettleNothing() throws {
        let pending = [try request(1, bash)]
        for name in ["Notification", "PreCompact", "SubagentStop", "PermissionRequest"] {
            let other = try event(#"{"session_id":"s","hook_event_name":"\#(name)","tool_name":"Bash"}"#)
            XCTAssertEqual(ApprovalSettle.settled(pending, by: other), [], name)
        }
    }

    func testTheWaitingCallIsFoundAmongOpenCalls() throws {
        let waiting = try request(1, bash)
        var calls = TranscriptCalls()
        let use =
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","#
            + #""input":{"command":"ls"}}]}}"#
        XCTAssertFalse(ApprovalSettle.waits(waiting, in: calls))
        _ = calls.add(complete: Data((use + "\n").utf8))
        XCTAssertTrue(ApprovalSettle.waits(waiting, in: calls))
        XCTAssertFalse(
            ApprovalSettle.waits(try request(2, bash.replacingOccurrences(of: "ls", with: "pwd")), in: calls))
    }

    func testNewSpendSettlesOnlyWhenNoSubagentCouldHaveSpent() {
        // Tool hooks count subagents, so their word is enough.
        XCTAssertTrue(ApprovalSettle.spendMeansAnswered(toolHooks: true, subagentCallOpen: nil, subagentAsked: false))
        // Without them, the transcript has to show no subagent call open and none asked.
        XCTAssertTrue(
            ApprovalSettle.spendMeansAnswered(toolHooks: false, subagentCallOpen: false, subagentAsked: false))
        XCTAssertFalse(
            ApprovalSettle.spendMeansAnswered(toolHooks: false, subagentCallOpen: true, subagentAsked: false))
        XCTAssertFalse(
            ApprovalSettle.spendMeansAnswered(toolHooks: false, subagentCallOpen: false, subagentAsked: true))
        // The transcript wasn't read yet.
        XCTAssertFalse(ApprovalSettle.spendMeansAnswered(toolHooks: false, subagentCallOpen: nil, subagentAsked: false))
    }

    func testASubagentCallIsSeenOpen() {
        var calls = TranscriptCalls()
        XCTAssertFalse(calls.subagentRunning)
        let task =
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t9","name":"Task","#
            + #""input":{"prompt":"look"}}]}}"#
        _ = calls.add(complete: Data((task + "\n").utf8))
        XCTAssertTrue(calls.subagentRunning)
    }

    func testAHookEndingAtItsTimeoutTimedOut() {
        // Claude Code stops the hook at its timeout; the hook started a moment before Wisp heard of it.
        XCTAssertTrue(ApprovalSettle.timedOut(elapsed: 119.5, hookTimeout: 120))
        XCTAssertTrue(ApprovalSettle.timedOut(elapsed: 130, hookTimeout: 120))
        XCTAssertFalse(ApprovalSettle.timedOut(elapsed: 12, hookTimeout: 120))
        XCTAssertFalse(ApprovalSettle.timedOut(elapsed: 110, hookTimeout: 120))
    }
}
