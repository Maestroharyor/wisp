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

    func testOtherEventsSettleNothing() throws {
        let pending = [try request(1, bash)]
        for name in ["Notification", "PreCompact", "SubagentStop", "PermissionRequest"] {
            let other = try event(#"{"session_id":"s","hook_event_name":"\#(name)","tool_name":"Bash"}"#)
            XCTAssertEqual(ApprovalSettle.settled(pending, by: other), [], name)
        }
    }
}
