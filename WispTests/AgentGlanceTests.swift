import XCTest

@testable import WispCore

final class PromptTextTests: XCTestCase {
    func testCollapsesWhitespaceToOneLine() {
        XCTAssertEqual(PromptText.trimmed("  fix the\n\n  login   bug\t "), "fix the login bug")
    }

    func testEmptyOrMissingIsNil() {
        XCTAssertNil(PromptText.trimmed(nil))
        XCTAssertNil(PromptText.trimmed(" \n\t "))
    }

    func testLongPromptIsCapped() throws {
        let text = try XCTUnwrap(PromptText.trimmed(String(repeating: "word ", count: 200)))
        XCTAssertEqual(text.count, PromptText.limit)
        XCTAssertTrue(text.hasSuffix("…"))
    }

    func testSecretsAreMasked() {
        XCTAssertEqual(PromptText.trimmed("use GITHUB_TOKEN=abc123 to push"), "use GITHUB_TOKEN=••• to push")
    }
}

final class SessionGlanceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ kind: String, extra: String = "") throws -> AgentEvent {
        try AgentEvent.decode(Data(#"{"session_id":"s","cwd":"/p/app","hook_event_name":"\#(kind)"\#(extra)}"#.utf8))
    }

    private func session(_ events: [(String, String)]) throws -> AgentSession {
        var sessions = AgentSessions()
        for (kind, extra) in events { sessions.apply(try event(kind, extra: extra), at: start) }
        return try XCTUnwrap(sessions.session("s"))
    }

    func testPromptIsKeptFromUserPromptSubmit() throws {
        let session = try session([("UserPromptSubmit", #","prompt":"Add rate limiting\nto the API""#)])
        XCTAssertEqual(session.lastPrompt, "Add rate limiting to the API")
        let glance = SessionGlance.make(session, now: start, hidden: false)
        XCTAssertEqual(glance.prompt, "You: Add rate limiting to the API")
    }

    func testPromptIsHiddenWhenPrivate() throws {
        let session = try session([("UserPromptSubmit", #","prompt":"secret plan""#)])
        XCTAssertNil(SessionGlance.make(session, now: start, hidden: true).prompt)
    }

    func testNewPromptWithoutTextClearsTheOldOne() throws {
        let session = try session([
            ("UserPromptSubmit", #","prompt":"first""#), ("Stop", ""), ("UserPromptSubmit", ""),
        ])
        XCTAssertNil(session.lastPrompt)
    }

    func testSessionStartClearsThePrompt() throws {
        let session = try session([
            ("UserPromptSubmit", #","prompt":"first""#), ("SessionStart", #","source":"clear""#),
        ])
        XCTAssertNil(session.lastPrompt)
    }

    func testPromptFieldIsReadOnlyFromPromptEvents() throws {
        let event = try event("Notification", extra: #","prompt":"not a prompt""#)
        XCTAssertNil(event.promptText)
    }

    func testGeminiAndCopilotPromptsAreRead() throws {
        let gemini = try AgentEvent.decode(
            Data(#"{"wisp_source":"gemini","session_id":"g","hook_event_name":"BeforeAgent","prompt":"hi"}"#.utf8))
        XCTAssertEqual(gemini.promptText, "hi")
        let copilot = try AgentEvent.decode(
            Data(
                #"{"wisp_source":"copilot","sessionId":"c","hook_event_name":"userPromptSubmitted","prompt":"yo"}"#.utf8
            ))
        XCTAssertEqual(copilot.promptText, "yo")
        let cursor = try AgentEvent.decode(
            Data(
                #"{"wisp_source":"cursor","conversation_id":"k","hook_event_name":"beforeSubmitPrompt","prompt":"go"}"#
                    .utf8))
        XCTAssertEqual(cursor.promptText, "go")
    }

    func testRunningToolIsTheActivity() throws {
        let session = try session([
            ("UserPromptSubmit", ""),
            ("PreToolUse", #","tool_name":"Edit","tool_input":{"file_path":"/p/app/middleware.ts"}"#),
        ])
        let glance = SessionGlance.make(session, now: start, hidden: false)
        XCTAssertEqual(glance.activity.text, "Editing middleware.ts")
        XCTAssertEqual(SessionGlance.make(session, now: start, hidden: true).activity.text, "Editing a file")
    }

    func testStatesReadAsActivities() throws {
        XCTAssertEqual(
            SessionGlance.make(try session([("SessionStart", "")]), now: start, hidden: false).activity, .ready)
        XCTAssertEqual(
            SessionGlance.make(try session([("UserPromptSubmit", "")]), now: start, hidden: false).activity, .working)
        let done = SessionGlance.make(try session([("UserPromptSubmit", ""), ("Stop", "")]), now: start, hidden: false)
        XCTAssertEqual(done.activity, .done)
        XCTAssertEqual(done.activity.text, "Done, click to jump")
        let asking = try session([
            ("UserPromptSubmit", ""), ("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"ls"}"#),
        ])
        XCTAssertEqual(SessionGlance.make(asking, now: start, hidden: false).activity, .approval)
        let compacting = try session([("UserPromptSubmit", ""), ("PreCompact", "")])
        XCTAssertEqual(SessionGlance.make(compacting, now: start, hidden: false).activity, .compacting)
    }

    func testAgentAndAge() throws {
        let glance = SessionGlance.make(
            try session([("UserPromptSubmit", "")]), now: start.addingTimeInterval(27 * 60 + 5), hidden: false)
        XCTAssertEqual(glance.agent, "Claude Code")
        XCTAssertEqual(glance.age, "27m")
    }

    func testAgeFormat() {
        XCTAssertEqual(SessionGlance.age(20), "now")
        XCTAssertEqual(SessionGlance.age(-5), "now")
        XCTAssertEqual(SessionGlance.age(61), "1m")
        XCTAssertEqual(SessionGlance.age(3 * 3600 + 100), "3h")
        XCTAssertEqual(SessionGlance.age(2 * 86_400 + 5), "2d")
    }
}

final class LimitSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testBothWindowsWithReset() {
        let readings = [
            UsageReading(window: .fiveHour, percent: 42.4, resets: now.addingTimeInterval(2 * 3600 + 10 * 60)),
            UsageReading(window: .sevenDay, percent: 61, resets: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
        ]
        let items = LimitSummary.make(readings, now: now)
        XCTAssertEqual(items.map(\.label), ["5 h", "7 d"])
        XCTAssertEqual(items.map(\.percent), [42, 61])
        XCTAssertEqual(items.map(\.resetsIn), ["2h 10m", "3d 4h"])
    }

    func testNothingKnownIsEmpty() {
        XCTAssertEqual(LimitSummary.make([], now: now), [])
        let stale = [UsageReading(window: .fiveHour, percent: 50, resets: now)]
        XCTAssertEqual(LimitSummary.make(stale, now: now), [])
    }

    func testUnknownResetAndStaleWindows() {
        let readings = [
            UsageReading(window: .fiveHour, percent: 10, resets: nil),
            UsageReading(window: .sevenDay, percent: 90, resets: now.addingTimeInterval(-60)),
        ]
        let items = LimitSummary.make(readings, now: now)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].resetsIn)
    }

    func testOtherAgentsAreNamedAndPercentIsClamped() {
        let items = LimitSummary.make(
            [UsageReading(window: .fiveHour, percent: 130, resets: nil, source: .codex)], now: now)
        XCTAssertEqual(items.first?.label, "Codex 5 h")
        XCTAssertEqual(items.first?.percent, 100)
    }

    func testRemainingFormat() {
        XCTAssertEqual(LimitSummary.remaining(30), "1m")
        XCTAssertEqual(LimitSummary.remaining(12 * 60), "12m")
        XCTAssertEqual(LimitSummary.remaining(3 * 3600), "3h")
        XCTAssertEqual(LimitSummary.remaining(3 * 3600 + 5 * 60), "3h 5m")
        XCTAssertEqual(LimitSummary.remaining(2 * 86_400), "2d")
    }
}

final class InlineDiffTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testEditCountsAndPicksBothSides() throws {
        let input = try json(
            #"{"file_path":"/a.ts","old_string":"a\nb\nc\nd\nkeep","new_string":"w\nx\ny\nz\nkeep"}"#)
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Edit", input: input))
        XCTAssertEqual(diff.added, 4)
        XCTAssertEqual(diff.removed, 4)
        XCTAssertEqual(diff.counts, "+4 −4")
        XCTAssertEqual(diff.lines.map(\.kind), [.removed, .removed, .added])
        XCTAssertEqual(diff.lines.map(\.text), ["a", "b", "w"])
        XCTAssertEqual(diff.lines.map(\.number), [nil, nil, nil])
    }

    func testWriteIsAllAddedWithLineNumbers() throws {
        let input = try json(#"{"file_path":"/a.txt","content":"one\ntwo\nthree\nfour\n"}"#)
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Write", input: input))
        XCTAssertEqual(diff.added, 4)
        XCTAssertEqual(diff.removed, 0)
        XCTAssertEqual(diff.lines.map(\.number), [1, 2, 3])
        XCTAssertEqual(diff.lines.map(\.text), ["one", "two", "three"])
        // A Write may replace a file whose old lines the request doesn't carry.
        XCTAssertTrue(diff.wholeFile)
        XCTAssertEqual(diff.counts, "4 lines")
    }

    func testWriteStripsCarriageReturnsAndCountsALastLineWithoutNewline() throws {
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Write", input: .object(["content": .string("a\r\nb\r\nc")])))
        XCTAssertEqual(diff.added, 3)
        XCTAssertEqual(diff.lines.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(
            InlineDiff.make(tool: "Write", input: .object(["content": .string("one")]))?.counts, "1 line")
    }

    func testDeletionCountsOnlyRemovedLines() throws {
        let input = try json(#"{"old_string":"a\nb","new_string":""}"#)
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Edit", input: input))
        XCTAssertEqual(diff.counts, "+0 −2")
        XCTAssertEqual(diff.lines.map(\.text), ["a", "b"])
    }

    func testInsertionCountsOnlyAddedLines() throws {
        let input = try json(#"{"old_string":"","new_string":"x\ny\nz"}"#)
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Edit", input: input))
        XCTAssertEqual(diff.counts, "+3 −0")
        XCTAssertEqual(diff.lines.map(\.kind), [.added, .added, .added])
    }

    func testTwoSeparatedChangesCountOnlyTheChangedLines() throws {
        let old = (1...20).map { "line \($0)" }
        var new = old
        new[1] = "changed 2"
        new[18] = "changed 19"
        let input = JSONValue.object([
            "old_string": .string(old.joined(separator: "\n")), "new_string": .string(new.joined(separator: "\n")),
        ])
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Edit", input: input))
        XCTAssertEqual(diff.counts, "+2 −2")
        XCTAssertEqual(diff.lines.map(\.text), ["line 2", "line 19", "changed 2"])
    }

    func testHugeEditsFallBackToTrimming() {
        let old = (0..<400).map { "a\($0)" }
        var new = old
        new[10] = "x"
        new[390] = "y"
        let changes = LineDiff.changes(old: old, new: new, cap: 100)
        // Over the cap only the shared start and end are dropped, so everything between counts.
        XCTAssertEqual(changes.removed.count, 381)
        XCTAssertEqual(LineDiff.changes(old: old, new: new).removed, ["a10", "a390"])
        XCTAssertEqual(LineDiff.changes(old: old, new: new).added, ["x", "y"])
    }

    func testLinesOfEmptyAndNewlineEndedText() {
        XCTAssertEqual(LineDiff.lines(""), [])
        XCTAssertEqual(LineDiff.lines("a\n"), ["a"])
        XCTAssertEqual(LineDiff.lines("a\n\nb"), ["a", "", "b"])
    }

    func testMultiEditAddsUpEveryEdit() throws {
        let input = try json(
            #"{"file_path":"/a","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c\nd","new_string":"e"}]}"#)
        let diff = try XCTUnwrap(InlineDiff.make(tool: "MultiEdit", input: input))
        XCTAssertEqual(diff.added, 2)
        XCTAssertEqual(diff.removed, 3)
    }

    func testCodexPatch() throws {
        let patch = "*** Begin Patch\n*** Update File: a.py\n@@\n-old\n+new\n+more\n context\n*** End Patch"
        let input = JSONValue.object(["command": .string(patch)])
        let diff = try XCTUnwrap(InlineDiff.make(tool: "apply_patch", input: input))
        XCTAssertEqual(diff.added, 2)
        XCTAssertEqual(diff.removed, 1)
        XCTAssertEqual(diff.lines.map(\.text), ["old", "new", "more"])
    }

    func testOnlyAddedWhenNothingRemoved() throws {
        let input = try json(#"{"old_string":"x","new_string":"x\n1\n2\n3\n4"}"#)
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Edit", input: input))
        XCTAssertEqual(diff.lines.map(\.kind), [.added, .added, .added])
    }

    func testOtherToolsAndNoChangeHaveNoDiff() throws {
        XCTAssertNil(InlineDiff.make(tool: "Bash", input: try json(#"{"command":"ls"}"#)))
        XCTAssertNil(InlineDiff.make(tool: "Edit", input: try json(#"{"old_string":"a","new_string":"a"}"#)))
        XCTAssertNil(InlineDiff.make(tool: "Write", input: try json(#"{"content":"  \n"}"#)))
    }

    func testLongLinesAreCut() throws {
        let long = String(repeating: "x", count: 500)
        let diff = try XCTUnwrap(InlineDiff.make(tool: "Write", input: .object(["content": .string(long)])))
        XCTAssertEqual(diff.lines.first?.text.count, InlineDiff.lineLimit)
    }
}

final class ApprovalKeyHintTests: XCTestCase {
    func testHintsFollowTheKeyStyle() {
        XCTAssertEqual(ApprovalKeys.hint(.allow, hyper: true), "⇪ Y")
        XCTAssertEqual(ApprovalKeys.hint(.deny, hyper: true), "⇪ N")
        XCTAssertEqual(ApprovalKeys.hint(.allow, hyper: false), "⌃⌥⌘Y")
        XCTAssertEqual(ApprovalKeys.hint(.pick(0), hyper: false), "⌃⌥⌘1")
        XCTAssertEqual(ApprovalKeys.hint(.pick(8), hyper: true), "⇪ 9")
        XCTAssertNil(ApprovalKeys.hint(.pick(9), hyper: true))
        XCTAssertEqual(ApprovalKeys.hint(.send, hyper: true), "⇪ Y")
    }
}
