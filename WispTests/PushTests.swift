import XCTest

@testable import WispCore

final class PushPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testAwayIsLockedOrIdleLongEnough() {
        XCTAssertTrue(PushPolicy.isAway(locked: true, idleSeconds: 0, idleMinutes: 2))
        XCTAssertTrue(PushPolicy.isAway(locked: false, idleSeconds: 120, idleMinutes: 2))
        XCTAssertFalse(PushPolicy.isAway(locked: false, idleSeconds: 119, idleMinutes: 2))
        // Zero minutes would mean always away; it's treated as one.
        XCTAssertFalse(PushPolicy.isAway(locked: false, idleSeconds: 30, idleMinutes: 0))
    }

    func testAwayModeHoldsBackWhileAtTheMac() {
        var policy = PushPolicy()
        XCTAssertEqual(policy.mode, .away)
        XCTAssertFalse(policy.allow(.approval, key: "a", away: false, now: now))
        XCTAssertTrue(policy.allow(.approval, key: "a", away: true, now: now))
    }

    func testHeldBackApprovalCanStillGoOnceAway() {
        var policy = PushPolicy()
        XCTAssertFalse(policy.allow(.approval, key: "a", away: false, now: now))
        XCTAssertFalse(policy.sent(approval: "a"))
        XCTAssertTrue(policy.allow(.approval, key: "a", away: true, now: now.addingTimeInterval(150)))
        XCTAssertTrue(policy.sent(approval: "a"))
    }

    func testAlwaysModeIgnoresAway() {
        var policy = PushPolicy(mode: .always)
        XCTAssertTrue(policy.allow(.needsYou, key: "s", away: false, now: now))
    }

    func testKindsHaveTheirOwnSwitches() {
        var policy = PushPolicy(kinds: [.approval], mode: .always)
        XCTAssertFalse(policy.allow(.done, key: "s", away: true, now: now))
        XCTAssertFalse(policy.allow(.budget, key: "x", away: true, now: now))
        XCTAssertTrue(policy.allow(.approval, key: "a", away: true, now: now))
        XCTAssertFalse(PushKind.defaults.contains(.done))
    }

    func testAnApprovalIsNeverSentTwice() {
        var policy = PushPolicy(mode: .always)
        XCTAssertTrue(policy.allow(.approval, key: "a", away: true, now: now))
        XCTAssertFalse(policy.allow(.approval, key: "a", away: true, now: now.addingTimeInterval(3600)))
        XCTAssertTrue(policy.allow(.approval, key: "b", away: true, now: now))
    }

    func testDoneAtMostOncePerSessionPerMinute() {
        var policy = PushPolicy(kinds: [.done], mode: .always)
        XCTAssertTrue(policy.allow(.done, key: "s1", away: true, now: now))
        XCTAssertFalse(policy.allow(.done, key: "s1", away: true, now: now.addingTimeInterval(59)))
        XCTAssertTrue(policy.allow(.done, key: "s2", away: true, now: now.addingTimeInterval(1)))
        XCTAssertTrue(policy.allow(.done, key: "s1", away: true, now: now.addingTimeInterval(60)))
    }

    func testHourlyCapStopsFloodsButNotApprovals() {
        var policy = PushPolicy(kinds: Set(PushKind.allCases), mode: .always)
        for index in 0..<PushPolicy.hourlyCap {
            XCTAssertTrue(policy.allow(.done, key: "s\(index)", away: true, now: now))
        }
        XCTAssertFalse(policy.allow(.done, key: "late", away: true, now: now))
        XCTAssertTrue(policy.allow(.approval, key: "a", away: true, now: now))
        XCTAssertTrue(policy.allow(.done, key: "late", away: true, now: now.addingTimeInterval(3600)))
    }

    func testMomentsKeyAndKind() {
        let done = AgentMoment.done(session: "s", project: "wisp", source: .claude)
        XCTAssertEqual(done.kind, .done)
        XCTAssertEqual(done.key, "s")
        XCTAssertEqual(AgentMoment.limit("5 h limit 82%").key, "5 h limit 82%")
        XCTAssertEqual(done.notice(hidden: false).message, "Claude Code finished in wisp.")
        XCTAssertEqual(done.notice(hidden: true).message, "Claude Code finished.")
    }
}

final class PushTopicTests: XCTestCase {
    func testTopicsAre128BitsURLSafe() {
        let topic = PushTopic.random()
        XCTAssertEqual(topic.count, 22)
        XCTAssertTrue(PushTopic.isValid(topic))
        XCTAssertNotEqual(topic, PushTopic.random())
    }

    func testValidation() {
        XCTAssertFalse(PushTopic.isValid(""))
        XCTAssertFalse(PushTopic.isValid("has space"))
        XCTAssertFalse(PushTopic.isValid("a/b"))
        XCTAssertFalse(PushTopic.isValid("é"))
        XCTAssertFalse(PushTopic.isValid(String(repeating: "a", count: 65)))
        XCTAssertTrue(PushTopic.isValid("abc-DEF_123"))
    }

    func testServerCleanUp() {
        XCTAssertEqual(PushTopic.server(" https://ntfy.sh/ ")?.absoluteString, "https://ntfy.sh")
        XCTAssertEqual(PushTopic.server("https://example.com/ntfy")?.absoluteString, "https://example.com/ntfy")
        XCTAssertNil(PushTopic.server("http://ntfy.sh"))
        XCTAssertNil(PushTopic.server("ntfy.sh"))
        XCTAssertNil(PushTopic.server("https://"))
        XCTAssertNil(PushTopic.server("https://ntfy.sh?x=1"))
        XCTAssertNil(PushTopic.server("https://user:pw@ntfy.sh"))
    }

    func testURLs() throws {
        let server = try XCTUnwrap(PushTopic.server("https://ntfy.sh"))
        XCTAssertEqual(PushTopic.url(server: server, topic: "abc")?.absoluteString, "https://ntfy.sh/abc")
        XCTAssertEqual(PushTopic.streamURL(server: server, topic: "abc")?.absoluteString, "https://ntfy.sh/abc/json")
        XCTAssertNil(PushTopic.url(server: server, topic: "../x"))
    }
}

final class PushMessageTests: XCTestCase {
    private func reply(token: String? = nil) throws -> PushMessage.Reply {
        PushMessage.Reply(
            url: try XCTUnwrap(URL(string: "https://ntfy.sh/replytopic")), nonce: "nonce123", token: token)
    }

    private let bash = PushMessage.Approval(
        agent: "Claude Code", tool: "Bash", prompt: .tool,
        summary: "GITHUB_TOKEN=abc123 curl https://api.example.com /Users/me/secret-project", project: "wisp")

    func testApprovalIsMaskedByDefault() throws {
        let notice = PushMessage.approval(
            bash, reply: try reply(), hidden: false, includeDetails: false, sequenceID: "q")
        XCTAssertEqual(notice.message, "Claude Code wants to run a command in wisp.")
        XCTAssertEqual(notice.priority, 4)
        XCTAssertEqual(notice.sequenceID, "q")
        XCTAssertFalse(notice.message.contains("curl"))
    }

    func testPrivateModeHidesTheProjectAndDetails() throws {
        let notice = PushMessage.approval(bash, reply: try reply(), hidden: true, includeDetails: true, sequenceID: "q")
        XCTAssertEqual(notice.message, "Claude Code wants to run a command.")
    }

    func testDetailsAreMasked() throws {
        let notice = PushMessage.approval(
            bash, reply: try reply(), hidden: false, includeDetails: true, sequenceID: "q")
        XCTAssertTrue(notice.message.contains("GITHUB_TOKEN=•••"))
        XCTAssertFalse(notice.message.contains("abc123"))
    }

    func testFileDetailsAreNamesNotPaths() {
        XCTAssertEqual(PushMessage.detail(tool: "Edit", summary: "/Users/me/work/App.swift"), "App.swift")
        XCTAssertEqual(PushMessage.detail(tool: "WebFetch", summary: "https://example.com/a?b=c"), "example.com")
        XCTAssertNil(PushMessage.detail(tool: "Bash", summary: ""))
        XCTAssertEqual(PushMessage.detail(tool: "Bash", summary: "ls\nrm -rf x"), "ls")
        let long = PushMessage.detail(tool: "Bash", summary: String(repeating: "a ", count: 200))
        XCTAssertEqual(long?.count, PushMessage.detailLimit)
    }

    func testPlansNeverCarryTheirText() throws {
        let plan = PushMessage.Approval(
            agent: "Claude Code", tool: "ExitPlanMode", prompt: .plan, summary: "Rewrite the billing code",
            project: "wisp")
        let notice = PushMessage.approval(
            plan, reply: try reply(), hidden: false, includeDetails: true, sequenceID: "q")
        XCTAssertEqual(notice.title, "Approve plan")
        XCTAssertFalse(notice.message.contains("billing"))
    }

    func testActionsPostTheNonceToTheReplyTopic() throws {
        let notice = PushMessage.approval(
            bash, reply: try reply(), hidden: false, includeDetails: false, sequenceID: "q")
        XCTAssertEqual(notice.actions.map(\.label), ["Allow", "Deny"])
        XCTAssertEqual(notice.actions.first?.url, "https://ntfy.sh/replytopic")
        XCTAssertEqual(notice.actions.first?.body, #"{"decision":"allow","nonce":"nonce123"}"#)
        XCTAssertEqual(notice.actions.last?.body, #"{"decision":"deny","nonce":"nonce123"}"#)
        XCTAssertEqual(notice.actions.first?.headers, [:])
    }

    func testTokenGoesInTheActionsHeaders() throws {
        let notice = PushMessage.approval(
            bash, reply: try reply(token: "tk_x"), hidden: false, includeDetails: false, sequenceID: "q")
        XCTAssertEqual(notice.actions.first?.headers, ["Authorization": "Bearer tk_x"])
    }

    func testPublishJSON() throws {
        let notice = PushMessage.approval(
            bash, reply: try reply(), hidden: false, includeDetails: false, sequenceID: "q")
        let value = try JSONDecoder().decode(JSONValue.self, from: PushMessage.json(topic: "pub", notice: notice))
        XCTAssertEqual(value["topic"]?.stringValue, "pub")
        XCTAssertEqual(value["priority"]?.intValue, 4)
        XCTAssertEqual(value["sequence_id"]?.stringValue, "q")
        XCTAssertEqual(value["tags"]?[0]?.stringValue, "lock")
        let allow = try XCTUnwrap(value["actions"]?[0])
        XCTAssertEqual(allow["action"]?.stringValue, "http")
        XCTAssertEqual(allow["method"]?.stringValue, "POST")
        XCTAssertEqual(allow["clear"], .bool(true))
        XCTAssertNil(allow["headers"])
    }

    func testSimpleNoticesHaveNoActions() throws {
        let value = try JSONDecoder().decode(
            JSONValue.self, from: PushMessage.json(topic: "pub", notice: PushMessage.test))
        XCTAssertNil(value["actions"])
        XCTAssertNil(value["sequence_id"])
        XCTAssertEqual(
            PushMessage.needsYou(agent: "Codex", project: "api", hidden: false).message,
            "Codex is waiting for you in api.")
        XCTAssertEqual(PushMessage.settled(sequenceID: "q", answered: true).sequenceID, "q")
    }

    func testVerbs() {
        XCTAssertEqual(PushMessage.verb(tool: "Write", prompt: .tool), "edit a file")
        XCTAssertEqual(PushMessage.verb(tool: "mcp__github__create_issue", prompt: .tool), "use a tool")
        XCTAssertEqual(PushMessage.verb(tool: "ExitPlanMode", prompt: .plan), "start on a plan")
    }
}

final class PushReplyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func line(_ body: String, event: String = "message") throws -> String {
        let value: JSONValue = .object([
            "id": .string("m1"), "time": .number(1), "event": .string(event), "topic": .string("reply"),
            "message": .string(body),
        ])
        return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func replies() -> PushReplies<Int> {
        var replies = PushReplies<Int>()
        replies.register(nonce: "good", for: 1, expires: now.addingTimeInterval(600))
        return replies
    }

    func testKnownNonceResolvesOnce() throws {
        var replies = replies()
        let allow = try line(PushMessage.replyBody(nonce: "good", decision: .allow))
        let result = replies.resolve(line: allow, now: now)
        XCTAssertEqual(result?.id, 1)
        XCTAssertEqual(result?.decision, .allow)
        XCTAssertNil(replies.resolve(line: allow, now: now))
        XCTAssertTrue(replies.isEmpty)
    }

    func testDeny() throws {
        var replies = replies()
        XCTAssertEqual(
            replies.resolve(line: try line(PushMessage.replyBody(nonce: "good", decision: .deny)), now: now)?.decision,
            .deny)
    }

    func testUnknownNonceDoesNothing() throws {
        var replies = replies()
        XCTAssertNil(
            replies.resolve(line: try line(PushMessage.replyBody(nonce: "forged", decision: .allow)), now: now))
        XCTAssertEqual(replies.count, 1)
    }

    func testExpiredApprovalIsIgnored() throws {
        var replies = replies()
        let late = now.addingTimeInterval(601)
        XCTAssertNil(replies.resolve(line: try line(PushMessage.replyBody(nonce: "good", decision: .allow)), now: late))
        var other = self.replies()
        other.removeExpired(now: late)
        XCTAssertTrue(other.isEmpty)
    }

    func testRemovedApprovalIsIgnored() throws {
        var replies = replies()
        replies.remove(1)
        XCTAssertNil(replies.resolve(line: try line(PushMessage.replyBody(nonce: "good", decision: .allow)), now: now))
    }

    func testMalformedLinesAreIgnored() throws {
        var replies = replies()
        for bad in [
            "", "not json", "[]", #"{"event":"keepalive"}"#, try line("allow good"),
            try line(#"{"nonce":"good","decision":"maybe"}"#), try line(#"{"nonce":"good"}"#),
            try line(#"{"nonce":"go od","decision":"allow"}"#),
            try line(PushMessage.replyBody(nonce: "good", decision: .allow), event: "open"),
            try line(#"{"nonce":"good","decision":"allow","pad":""# + String(repeating: "x", count: 600) + #""}"#),
        ] {
            XCTAssertNil(replies.resolve(line: bad, now: now), bad)
        }
        XCTAssertEqual(replies.count, 1)
    }

    func testExtraFieldsInTheBodyAreIgnored() throws {
        var replies = replies()
        let body = #"{"nonce":"good","decision":"allow","command":"rm -rf /"}"#
        XCTAssertEqual(replies.resolve(line: try line(body), now: now)?.decision, .allow)
    }
}
