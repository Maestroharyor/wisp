import XCTest

@testable import WispCore

final class ToolLabelTests: XCTestCase {
    private func label(_ tool: String?, _ input: ToolInput, hidden: Bool = false) -> String {
        ToolLabel.label(tool: tool, input: input, hidden: hidden)
    }

    func testEachToolGetsAVerb() {
        XCTAssertEqual(label("Bash", ToolInput(command: "npm test")), "Running npm test")
        XCTAssertEqual(label("Edit", ToolInput(filePath: "/Users/me/app/Hub.swift")), "Editing Hub.swift")
        XCTAssertEqual(label("Write", ToolInput(filePath: "/a/b/New.swift")), "Editing New.swift")
        XCTAssertEqual(label("MultiEdit", ToolInput(filePath: "/a/b/C.swift")), "Editing C.swift")
        XCTAssertEqual(label("NotebookEdit", ToolInput(notebookPath: "/a/n.ipynb")), "Editing n.ipynb")
        XCTAssertEqual(label("Read", ToolInput(filePath: "/a/README.md")), "Reading README.md")
        XCTAssertEqual(label("Grep", ToolInput(pattern: "TODO")), "Searching TODO")
        XCTAssertEqual(label("Glob", ToolInput(pattern: "**/*.swift")), "Searching **/*.swift")
        XCTAssertEqual(label("WebFetch", ToolInput(url: "https://docs.swift.org/x/y?z=1")), "Fetching docs.swift.org")
        XCTAssertEqual(label("WebSearch", ToolInput(query: "my private question")), "Searching the web")
        XCTAssertEqual(label("Task", ToolInput(subagentType: "Explore")), "Subagent: Explore")
        XCTAssertEqual(label("Agent", ToolInput(description: "Find callers")), "Subagent: Find callers")
        XCTAssertEqual(label("mcp__github__create_issue", ToolInput()), "github: create_issue")
        XCTAssertEqual(label("TodoWrite", ToolInput()), "TodoWrite")
        XCTAssertEqual(label(nil, ToolInput()), "Tool")
    }

    func testThePillGetsASymbolAndTheSubject() {
        let bash = ToolLabel.describe(tool: "Bash", input: ToolInput(command: "npm test"), hidden: false)
        XCTAssertEqual(bash, ToolDescription(symbol: "terminal", label: "Running npm test", short: "npm test"))
        let edit = ToolLabel.describe(tool: "Edit", input: ToolInput(filePath: "/a/Hub.swift"), hidden: true)
        XCTAssertEqual(edit, ToolDescription(symbol: "pencil", label: "Editing a file", short: "Editing"))
        XCTAssertEqual(
            ToolLabel.describe(tool: "WebSearch", input: ToolInput(), hidden: true).short, "Searching the web")
        XCTAssertEqual(ToolLabel.describe(tool: "mcp__x__y", input: ToolInput(), hidden: false).short, "x: y")
        XCTAssertEqual(
            ToolLabel.describe(tool: "Task", input: ToolInput(subagentType: "Plan"), hidden: false).short, "Plan")
        XCTAssertEqual(ToolLabel.describe(tool: "Bash", input: ToolInput(), hidden: false).short, "Running")
        let long = ToolLabel.describe(
            tool: "Bash", input: ToolInput(command: String(repeating: "a ", count: 50)), hidden: false)
        XCTAssertEqual(long.short.count, ToolLabel.shortLimit)
    }

    func testLongLabelsAreCutAndOnlyTheFirstLineShows() {
        let long = label("Bash", ToolInput(command: "xcodebuild -project Wisp.xcodeproj -scheme Wisp build"))
        XCTAssertEqual(long.count, ToolLabel.limit)
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertEqual(label("Bash", ToolInput(command: "git add .\ngit commit")), "Running git add .")
        XCTAssertEqual(label("Bash", ToolInput(command: "  ls  ")), "Running ls")
    }

    func testHiddenLabelsGiveNothingAway() {
        XCTAssertEqual(label("Bash", ToolInput(command: "cat secrets.txt"), hidden: true), "Running a command")
        XCTAssertEqual(label("Edit", ToolInput(filePath: "/a/Plan.md"), hidden: true), "Editing a file")
        XCTAssertEqual(label("Read", ToolInput(filePath: "/a/Plan.md"), hidden: true), "Reading a file")
        XCTAssertEqual(label("Grep", ToolInput(pattern: "acme"), hidden: true), "Searching files")
        XCTAssertEqual(label("WebFetch", ToolInput(url: "https://acme.com"), hidden: true), "Fetching a page")
        XCTAssertEqual(label("Task", ToolInput(description: "Acme deal"), hidden: true), "Running a subagent")
        XCTAssertEqual(label("mcp__github__create_issue", ToolInput(), hidden: true), "github: create_issue")
    }

    func testCommandsAreMasked() {
        XCTAssertEqual(
            label("Bash", ToolInput(command: "GITHUB_TOKEN=abc123 gh api")), "Running GITHUB_TOKEN=••• gh api")
    }

    func testMaskingRules() {
        let cases: [(String, String)] = [
            ("GITHUB_TOKEN=abc123 gh api user", "GITHUB_TOKEN=••• gh api user"),
            ("export API_KEY='s3cr3t value'", "export API_KEY=•••"),
            ("DB_PASSWORD=\"hunter2\" ./run", "DB_PASSWORD=••• ./run"),
            ("aws_secret_access_key=xyz cmd", "aws_secret_access_key=••• cmd"),
            ("login --password hunter2 --user me", "login --password ••• --user me"),
            ("cli --token=abc --api-key xyz", "cli --token=••• --api-key •••"),
            ("mysql -u root -phunter2 db", "mysql -u root -p••• db"),
            ("curl -H 'Authorization: Bearer abc.def.ghi' x", "curl -H 'Authorization: Bearer •••' x"),
            ("curl -H \"Authorization: token abc\" x", "curl -H \"Authorization: token •••\" x"),
            ("git clone https://me:pw123@github.com/a/b", "git clone https://•••@github.com/a/b"),
            ("curl 'https://x.io/v1?user=1&api_key=abc&q=2'", "curl 'https://x.io/v1?user=1&api_key=•••&q=2'"),
            ("curl https://x.io/?token=abc", "curl https://x.io/?token=•••"),
            ("echo sk-ant-api03-abcdefghijkl", "echo •••"),
            ("echo sk-proj-abcdefghijklmnop", "echo •••"),
            ("gh auth login ghp_abcdefghijklmnop1234", "gh auth login •••"),
            ("echo github_pat_11ABCDEFG_abcdefgh", "echo •••"),
            ("curl -d token=xoxb-1234-5678-abcdef", "curl -d token=•••"),
            ("echo xoxp-1234-5678-abcdef", "echo •••"),
            ("aws configure AKIAABCDEFGHIJKLMNOP", "aws configure •••"),
            ("echo glpat-abcdefghij1234567890", "echo •••"),
            ("echo dGhpcyBpcyBhIHZlcnkgbG9uZyBzZWNyZXQgdG9rZW4x", "echo •••"),
            ("curl -u admin:hunter2 https://x.io", "curl -u admin:••• https://x.io"),
            ("curl --user me:pw https://x.io", "curl --user me:••• https://x.io"),
            ("curl -H 'X-Api-Key: abc123' x", "curl -H 'X-Api-Key: •••' x"),
            ("curl -H \"x-auth-token: abc\" x", "curl -H \"x-auth-token: •••\" x"),
            ("sshpass -p hunter2 ssh me@host", "sshpass -p ••• ssh me@host"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ToolLabel.mask(input), expected, input)
        }
    }

    func testSafeCommandsAreUnchanged() {
        for command in [
            "npm test", "mkdir -p build/out", "git commit -m 'Fix the key handler'", "ls -la ~/Documents",
            "swift build -c release", "make keyboard-test",
            "cat /Users/me/Documents/rea/wisp/WispCore/AgentEvent.swift",
            "open https://github.com/Maestroharyor/wisp/pull/14", "docker run -u 1000:1000 alpine",
        ] {
            XCTAssertEqual(ToolLabel.mask(command), command)
        }
    }
}

final class AgentToolSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    private func event(_ kind: String, session: String = "s1", extra: String = "") throws -> AgentEvent {
        try AgentEvent.decode(
            Data(#"{"session_id":"\#(session)","cwd":"/p/app","hook_event_name":"\#(kind)"\#(extra)}"#.utf8))
    }

    private func tool(_ kind: String, _ name: String, id: String, input: String = "{}") throws -> AgentEvent {
        try event(kind, extra: #","tool_name":"\#(name)","tool_use_id":"\#(id)","tool_input":\#(input)"#)
    }

    func testToolEventsDecode() throws {
        let pre = try tool("PreToolUse", "Bash", id: "t1", input: #"{"command":"ls","description":"List"}"#)
        XCTAssertEqual(pre.kind, .preToolUse)
        XCTAssertEqual(pre.toolUseID, "t1")
        XCTAssertEqual(pre.toolInput.command, "ls")
        XCTAssertEqual(try event("PostToolUse").kind, .postToolUse)
        XCTAssertEqual(try event("SubagentStop").kind, .subagentStop)
        let task = try tool("PreToolUse", "Task", id: "t2", input: #"{"subagent_type":"Explore","prompt":"x"}"#)
        XCTAssertEqual(task.toolInput.subagentType, "Explore")
    }

    func testParallelToolsKeepTheOneStillRunning() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Read", id: "a", input: #"{"file_path":"/x/A.swift"}"#), at: start)
        sessions.apply(try tool("PreToolUse", "Read", id: "b", input: #"{"file_path":"/x/B.swift"}"#), at: start)
        sessions.apply(try tool("PostToolUse", "Read", id: "b"), at: start + 1)
        XCTAssertEqual(sessions.session("s1")?.currentTool?.label, "Reading A.swift")
        sessions.apply(try tool("PostToolUse", "Read", id: "a"), at: start + 2)
        XCTAssertNil(sessions.session("s1")?.currentTool)
    }

    func testAFinishedToolLingersInThePill() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Bash", id: "a", input: #"{"command":"ls"}"#), at: start)
        sessions.apply(try tool("PostToolUse", "Bash", id: "a"), at: start + 10)
        let session = try XCTUnwrap(sessions.session("s1"))
        XCTAssertEqual(session.pillTool(now: start + 11)?.label, "Running ls")
        XCTAssertNil(session.pillTool(now: start + 10 + AgentSession.toolLinger))
        XCTAssertEqual(session.toolLingerEnds(now: start + 11), start + 10 + AgentSession.toolLinger)
        XCTAssertNil(session.toolLingerEnds(now: start + 12))
        sessions.apply(try event("Stop"), at: start + 10.5)
        XCTAssertNil(sessions.session("s1")?.pillTool(now: start + 10.6), "the end of a turn clears it at once")
    }

    func testToolActivityDoesNotReorderSessions() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit", session: "a"), at: start)
        sessions.apply(try event("UserPromptSubmit", session: "b"), at: start + 1)
        XCTAssertEqual(sessions.list.map(\.id), ["b", "a"])
        for second in 2..<6 {
            sessions.apply(
                try event("PreToolUse", session: "a", extra: #","tool_name":"Read","tool_use_id":"t\#(second)""#),
                at: start + TimeInterval(second))
        }
        XCTAssertEqual(sessions.list.map(\.id), ["b", "a"])
        // Waking a finished session is news, though.
        sessions.apply(try event("Stop", session: "a"), at: start + 7)
        sessions.apply(try event("Stop", session: "b"), at: start + 8)
        sessions.apply(try event("PreToolUse", session: "a", extra: #","tool_name":"Read""#), at: start + 9)
        XCTAssertEqual(sessions.list.map(\.id), ["a", "b"])
    }

    func testCurrentToolFollowsPreAndPost() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Bash", id: "t1", input: #"{"command":"npm test"}"#), at: start + 1)
        var session = try XCTUnwrap(sessions.session("s1"))
        XCTAssertEqual(session.currentTool?.label, "Running npm test")
        XCTAssertEqual(session.currentTool?.hiddenLabel, "Running a command")
        XCTAssertEqual(session.currentTool?.started, start + 1)
        XCTAssertEqual(session.toolCount, 1)
        XCTAssertEqual(session.timeline.count, 1, "tools stay out of the timeline")
        // A PostToolUse for another call leaves the current one alone.
        sessions.apply(try tool("PostToolUse", "Read", id: "other"), at: start + 2)
        XCTAssertNotNil(sessions.session("s1")?.currentTool)
        sessions.apply(try tool("PostToolUse", "Bash", id: "t1"), at: start + 3)
        session = try XCTUnwrap(sessions.session("s1"))
        XCTAssertNil(session.currentTool)
        XCTAssertEqual(session.state, .running)
    }

    func testAToolWakesASessionWispSawFinish() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("Stop"), at: start)
        sessions.apply(try tool("PreToolUse", "Read", id: "t1", input: #"{"file_path":"/a/b.swift"}"#), at: start + 5)
        let session = try XCTUnwrap(sessions.session("s1"))
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.turnStarted, start + 5)
        XCTAssertNil(session.turnEnded)
    }

    func testTheEndOfATurnClearsTheTool() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Task", id: "t1", input: #"{"subagent_type":"Explore"}"#), at: start)
        XCTAssertEqual(sessions.session("s1")?.subagents, 1)
        sessions.apply(try event("Stop"), at: start + 1)
        XCTAssertNil(sessions.session("s1")?.currentTool)
        XCTAssertEqual(sessions.session("s1")?.subagents, 0)
    }

    func testSubagentsCountDownAndNeverBelowZero() throws {
        var sessions = AgentSessions()
        sessions.apply(try tool("PreToolUse", "Task", id: "a", input: "{}"), at: start)
        sessions.apply(try tool("PreToolUse", "Agent", id: "b", input: "{}"), at: start)
        XCTAssertEqual(sessions.session("s1")?.subagents, 2)
        sessions.apply(try event("SubagentStop"), at: start + 1)
        sessions.apply(try event("SubagentStop"), at: start + 1)
        sessions.apply(try event("SubagentStop"), at: start + 1)
        XCTAssertEqual(sessions.session("s1")?.subagents, 0)
    }

    func testAPermissionRequestKeepsItsApproval() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try event("PermissionRequest", extra: #","tool_name":"Bash""#), at: start + 1)
        sessions.apply(try tool("PreToolUse", "Read", id: "t2"), at: start + 2)
        XCTAssertEqual(sessions.session("s1")?.state, .needsApproval)
    }

    func testADeniedToolIsCleared() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Bash", id: "t1", input: #"{"command":"rm -rf /"}"#), at: start)
        sessions.apply(try event("PermissionRequest", extra: #","tool_name":"Bash""#), at: start + 1)
        sessions.record(.denied, "Denied", session: "s1", at: start + 2)
        XCTAssertNil(sessions.session("s1")?.currentTool)
    }

    func testADenialDropsTheRequestedToolNotAParallelOne() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Bash", id: "b", input: #"{"command":"rm x"}"#), at: start)
        sessions.apply(try tool("PreToolUse", "Read", id: "r", input: #"{"file_path":"/a/R.swift"}"#), at: start)
        sessions.apply(try event("PermissionRequest", extra: #","tool_name":"Bash""#), at: start + 1)
        sessions.record(.denied, "Denied", session: "s1", at: start + 2)
        XCTAssertEqual(sessions.session("s1")?.runningTools.map(\.name), ["Read"])
    }

    func testLastActivityAndPruningCountToolCalls() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Read", id: "t"), at: start + 7200)
        let session = try XCTUnwrap(sessions.session("s1"))
        let facts = Dictionary(uniqueKeysWithValues: session.facts(now: start + 7205).map { ($0.label, $0.value) })
        XCTAssertEqual(facts["Last activity"], "just now")
        sessions.prune(now: start + 7300, olderThan: 3600)
        XCTAssertNotNil(sessions.session("s1"), "a session busy with tools isn't pruned")
    }

    func testToolFactsUseTheHiddenLabelInPrivate() throws {
        var sessions = AgentSessions()
        sessions.apply(try event("UserPromptSubmit"), at: start)
        sessions.apply(try tool("PreToolUse", "Bash", id: "t1", input: #"{"command":"ls"}"#), at: start)
        let session = try XCTUnwrap(sessions.session("s1"))
        let shown = Dictionary(uniqueKeysWithValues: session.facts(now: start + 12).map { ($0.label, $0.value) })
        XCTAssertEqual(shown["Current tool"], "Running ls · 12s")
        XCTAssertEqual(shown["Tools used"], "1")
        let hidden = Dictionary(
            uniqueKeysWithValues: session.facts(now: start + 12, hidden: true).map { ($0.label, $0.value) })
        XCTAssertEqual(hidden["Current tool"], "Running a command · 12s")
        XCTAssertNil(hidden["Subagents running"])
    }
}

final class AgentUrgencyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)

    private func session(
        _ id: String, _ state: AgentSession.State, since: TimeInterval, updated: TimeInterval? = nil,
        compacting: Bool = false
    ) -> AgentSession {
        var session = AgentSession(
            id: id, project: id, state: state, turnStarted: now, updated: now - (updated ?? since))
        session.stateSince = now - since
        session.compacting = compacting
        return session
    }

    func testAJustFinishedOrWaitingSessionWins() {
        let running = session("run", .running, since: 1)
        for state in [AgentSession.State.finished, .waiting] {
            let pick = AgentUrgency.pick([running, session("moment", state, since: 2)], now: now)
            XCTAssertEqual(pick.primary?.id, "moment")
            XCTAssertEqual(pick.others, 1)
        }
    }

    func testRunningBeatsAnOldMomentAndAnApproval() {
        let running = session("run", .running, since: 60)
        let pick = AgentUrgency.pick(
            [session("old", .waiting, since: 30), running, session("ask", .needsApproval, since: 1)], now: now)
        XCTAssertEqual(pick.primary?.id, "run")
        XCTAssertEqual(pick.others, 2, "the waiting and approval sessions still count")
    }

    func testCompactingCountsAsWork() {
        let pick = AgentUrgency.pick([session("idle", .idle, since: 1, compacting: true)], now: now)
        XCTAssertEqual(pick.primary?.id, "idle")
    }

    func testTiesGoToTheMostRecentlyUpdated() {
        let pick = AgentUrgency.pick(
            [session("a", .running, since: 50, updated: 9), session("b", .running, since: 50, updated: 1)], now: now)
        XCTAssertEqual(pick.primary?.id, "b")
        XCTAssertEqual(pick.others, 1)
    }

    func testNothingToShow() {
        XCTAssertNil(AgentUrgency.pick([], now: now).primary)
        let quiet = AgentUrgency.pick([session("a", .idle, since: 1), session("b", .finished, since: 60)], now: now)
        XCTAssertNil(quiet.primary)
        XCTAssertEqual(quiet.others, 0)
    }

    func testAnApprovalAloneStillPicksItsSession() {
        let pick = AgentUrgency.pick([session("ask", .needsApproval, since: 1)], now: now)
        XCTAssertEqual(pick.primary?.id, "ask")
        XCTAssertEqual(pick.others, 0)
    }

    func testTheBusiestSessionWinsATie() throws {
        var sessions = AgentSessions()
        let start = now
        let prompt = { (id: String) in
            try AgentEvent.decode(Data(#"{"session_id":"\#(id)","hook_event_name":"UserPromptSubmit"}"#.utf8))
        }
        sessions.apply(try prompt("a"), at: start)
        sessions.apply(try prompt("b"), at: start + 1)
        let read = try AgentEvent.decode(
            Data(#"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"Read","tool_use_id":"t"}"#.utf8))
        sessions.apply(read, at: start + 2)
        XCTAssertEqual(AgentUrgency.pick(sessions.list, now: start + 10).primary?.id, "a")
        XCTAssertEqual(sessions.list.first?.id, "b", "the list order stays")
    }

    func testNeedsYouBeatsDone() {
        let pick = AgentUrgency.pick(
            [session("ask", .waiting, since: 2, updated: 2), session("done", .finished, since: 1, updated: 1)], now: now
        )
        XCTAssertEqual(pick.primary?.id, "ask")
    }

    func testWhenTheMomentEnds() {
        XCTAssertEqual(
            AgentUrgency.momentEnds([session("a", .finished, since: 1), session("b", .running, since: 1)], now: now),
            now + AgentUrgency.moment - 1)
        XCTAssertNil(AgentUrgency.momentEnds([session("b", .running, since: 1)], now: now))
    }
}

final class ToolHookInstallTests: XCTestCase {
    private let command = "'/Applications/Wisp.app/Contents/Helpers/wisp-agent'"
    private let helper = "/Applications/Wisp.app/Contents/Helpers/wisp-agent"

    private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    func testToolHooksAreAddedOnlyWhenAskedAndRunInTheBackground() throws {
        let off = try json(HookInstaller.install(into: Data(), command: command))
        XCTAssertNil(off["hooks"]?["PreToolUse"])
        let onData = try HookInstaller.install(into: Data(), command: command, tools: true)
        let on = try json(onData)
        for event in ["PreToolUse", "PostToolUse", "SubagentStop"] {
            XCTAssertEqual(on["hooks"]?[event]?[0]?["hooks"]?[0]?["async"], .bool(true), event)
            XCTAssertEqual(on["hooks"]?[event]?[0]?["hooks"]?[0]?["timeout"], .number(5), event)
        }
        XCTAssertTrue(try HookInstaller.toolsInstalled(in: onData))
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: try HookInstaller.install(into: Data(), command: command)))
    }

    func testEitherChoiceIsUpToDate() throws {
        let off = try HookInstaller.install(into: Data(), command: command)
        let on = try HookInstaller.install(into: Data(), command: command, tools: true)
        XCTAssertEqual(try HookInstaller.link(in: off, helper: helper, source: .claude), .this)
        XCTAssertEqual(try HookInstaller.link(in: on, helper: helper, source: .claude), .this)
        // Turning tools off again drops exactly those three.
        let back = try HookInstaller.install(into: on, command: command, tools: false)
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: back))
        XCTAssertEqual(try json(back), try json(off))
    }

    func testTheUsersOwnToolHooksStay() throws {
        let mine = Data(
            #"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"my-guard"}]}]}}"#.utf8)
        let on = try HookInstaller.install(into: mine, command: command, tools: true)
        XCTAssertEqual(try json(on)["hooks"]?["PreToolUse"]?[0]?["hooks"]?[0]?["command"], .string("my-guard"))
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: mine))
        let removed = try json(HookInstaller.remove(from: on))
        XCTAssertEqual(removed["hooks"]?["PreToolUse"]?[0]?["hooks"]?[0]?["command"], .string("my-guard"))
        XCTAssertNil(removed["hooks"]?["PreToolUse"]?[1])
    }

    func testTheHelperSendsToolHooksWithoutWaiting() {
        XCTAssertEqual(AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"PreToolUse"}"#.utf8)), .tool)
        XCTAssertEqual(AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"PostToolUse"}"#.utf8)), .tool)
        XCTAssertEqual(AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"SubagentStop"}"#.utf8)), .tool)
        XCTAssertEqual(AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"PermissionRequest"}"#.utf8)), .hook)
        XCTAssertEqual(AgentProtocol.kind(forHook: Data("not json".utf8)), .hook)
    }

    func testToolMessagesDecodeAsHooks() throws {
        let payload = Data(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash"}"#.utf8)
        let message = try XCTUnwrap(
            AgentProtocol.envelope(kind: .tool, source: .claude, terminal: nil, payload: payload))
        guard case .hook(let event) = try AgentProtocol.decode(message) else { return XCTFail("not a hook") }
        XCTAssertEqual(event.kind, .preToolUse)
    }
}
