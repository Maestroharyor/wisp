import XCTest

@testable import WispCore

final class TranscriptCallsTests: XCTestCase {
    private let bashUse =
        #"{"type":"assistant","isSidechain":false,"message":{"id":"m1","role":"assistant","content":["#
        + #"{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"ls"}}]}}"#
    private let bashResult =
        #"{"type":"user","isSidechain":false,"message":{"role":"user","content":["#
        + #"{"type":"tool_result","tool_use_id":"toolu_1","content":"a\nb"}]}}"#

    private func lines(_ lines: String...) -> Data {
        Data(lines.map { $0 + "\n" }.joined().utf8)
    }

    func testACallFinishesWhenItsResultArrives() {
        var calls = TranscriptCalls()
        let started = calls.add(complete: lines(bashUse))
        XCTAssertEqual(started.finished, [])
        let finished = calls.add(complete: lines(bashResult))
        XCTAssertEqual(
            finished.finished, [TranscriptCalls.Call(tool: "Bash", input: .object(["command": .string("ls")]))])
        // Counted once.
        XCTAssertEqual(calls.add(complete: lines(bashResult)).finished, [])
    }

    func testARejectedCallFinishesToo() {
        // Answering No in the terminal writes an error result for the call.
        var calls = TranscriptCalls()
        let rejected =
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","#
            + #""is_error":true,"content":"The user doesn't want to proceed with this tool use."}]}}"#
        XCTAssertEqual(calls.add(complete: lines(bashUse, rejected)).finished.map(\.tool), ["Bash"])
    }

    func testAResultForAnUnknownCallIsIgnored() {
        var calls = TranscriptCalls()
        XCTAssertEqual(calls.add(complete: lines(bashResult)).finished, [])
    }

    func testSubagentLinesAreLeftOut() {
        // A subagent's calls share the main transcript in older versions; Wisp matches main-agent requests only.
        var calls = TranscriptCalls()
        let use = bashUse.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        let result = bashResult.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        XCTAssertEqual(calls.add(complete: lines(use, result)).finished, [])
    }

    func testOnlyMessagesCountNotRequestCopies() {
        // Claude Code also logs copies of what it sent the API, holding old calls and results.
        var calls = TranscriptCalls()
        let copy =
            #"{"type":"api-request-blob","message":{"content":["#
            + #"{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"ls"}},"#
            + #"{"type":"tool_result","tool_use_id":"toolu_1","content":"a"}]}}"#
        XCTAssertEqual(calls.add(complete: lines(copy)).finished, [])
        XCTAssertEqual(calls.add(complete: lines(bashUse, copy)).finished, [])
        XCTAssertEqual(calls.add(complete: lines(bashResult)).finished.map(\.tool), ["Bash"])
    }

    func testAPartialLineWaitsAndAPartialStartIsSkipped() {
        var calls = TranscriptCalls()
        // A read that starts mid-line (the window before the request) skips that fragment.
        let fragment = Data(#"put":{"command":"x"}}]}}"#.utf8) + Data("\n".utf8)
        let tail = Data(bashResult.prefix(20).utf8)
        let data = fragment + lines(bashUse) + tail
        let read = calls.add(complete: data)
        XCTAssertEqual(read.used, data.count - tail.count)
        XCTAssertEqual(read.finished, [])
        XCTAssertEqual(calls.add(complete: lines(bashResult)).finished.map(\.tool), ["Bash"])
    }

    func testParallelCallsFinishOneByOne() {
        var calls = TranscriptCalls()
        let both =
            #"{"type":"assistant","message":{"id":"m2","content":["#
            + #"{"type":"tool_use","id":"toolu_a","name":"Bash","input":{"command":"pwd"}},"#
            + #"{"type":"tool_use","id":"toolu_b","name":"Read","input":{"file_path":"/x"}}]}}"#
        let readDone =
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_b","content":"x"}]}}"#
        XCTAssertEqual(calls.add(complete: lines(both, readDone)).finished.map(\.tool), ["Read"])
    }
}
