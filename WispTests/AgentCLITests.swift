import XCTest

@testable import WispCore

final class AgentReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func session(_ id: String, _ state: AgentSession.State, active: TimeInterval) -> AgentSession {
        var session = AgentSession(
            id: id, project: "proj-\(id)", state: state, turnStarted: now - 125, updated: now - active)
        session.cwd = "/Users/me/\(id)"
        session.branch = "main"
        session.model = "Opus"
        session.contextPercent = 42
        session.cost = 1.5
        return session
    }

    private func running() throws -> AgentSession {
        var all = AgentSessions()
        let pre = #"""
            {"session_id":"a","cwd":"/Users/me/a","hook_event_name":"PreToolUse","tool_name":"Bash",
            "tool_use_id":"t1","tool_input":{"command":"TOKEN=abc ls"}}
            """#
        all.apply(try AgentEvent.decode(Data(pre.utf8)), at: now - 12)
        return try XCTUnwrap(all.session("a"))
    }

    func testRowsMapSessionFiguresNewestFirst() throws {
        let done = session("b", .finished, active: 60)
        let report = AgentReport.make(
            sessions: [done, try running()], spend: DailySpend(), query: .status, now: now, hidden: nil)
        XCTAssertEqual(report.sessions.map(\.id), ["a", "b"])
        let row = report.sessions[0]
        XCTAssertEqual(row.state, "working")
        XCTAssertEqual(row.agent, "Claude Code")
        XCTAssertEqual(row.tool, "Running TOKEN=••• ls")
        XCTAssertEqual(row.toolSeconds, 12)
        XCTAssertEqual(row.folder, "/Users/me/a")
        XCTAssertEqual(report.sessions[1].state, "done")
        XCTAssertNil(report.spend)
    }

    func testHiddenDropsIDsFoldersAndToolInput() throws {
        let report = AgentReport.make(
            sessions: [try running()], spend: DailySpend(), query: .status, now: now, hidden: "during a call")
        let row = report.sessions[0]
        XCTAssertNil(row.id)
        XCTAssertNil(row.folder)
        XCTAssertEqual(row.tool, "Running a command")
        XCTAssertEqual(row.project, "a")
        XCTAssertEqual(report.hidden, "during a call")
    }

    func testSpendOnlyWhenAsked() {
        var spend = DailySpend()
        spend.add(2, on: now, project: "wisp")
        let report = AgentReport.make(sessions: [], spend: spend, query: .spend, now: now, hidden: nil)
        XCTAssertEqual(report.spend?.today, 2)
        XCTAssertEqual(report.spend?.days.count, 7)
        XCTAssertEqual(report.spend?.projects.map(\.project), ["wisp"])
    }

    func testJSONRoundTripsWithStableKeys() throws {
        let report = AgentReport.make(
            sessions: [try running()], spend: DailySpend(), query: .spend, now: now, hidden: nil)
        let data = try XCTUnwrap(report.encoded())
        XCTAssertEqual(AgentReport.decode(data), report)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let top) = json, case .array(let rows) = top["sessions"], case .object(let row) = rows[0]
        else { return XCTFail("unexpected shape") }
        XCTAssertEqual(Set(top.keys), ["v", "generated", "hidden", "sessions", "spend"])
        // Unknown values are null rather than missing, so scripts see the same keys every time.
        XCTAssertEqual(
            Set(row.keys),
            [
                "id", "project", "branch", "agent", "state", "model", "contextPercent", "cost", "costIsReal", "tool",
                "toolSeconds", "turnSeconds", "folder",
            ])
        XCTAssertEqual(row["branch"], .null)
    }

    func testQueryMessagesDecode() throws {
        let status = try XCTUnwrap(
            AgentProtocol.envelope(kind: .query, source: .claude, terminal: nil, payload: AgentQuery.status.payload))
        XCTAssertEqual(try AgentProtocol.decode(status), .query(.status))
        let unknown = try XCTUnwrap(
            AgentProtocol.envelope(kind: .query, source: .claude, terminal: nil, payload: Data(#"{"query":"x"}"#.utf8)))
        XCTAssertEqual(try AgentProtocol.decode(unknown), .unsupported("query x"))
    }
}

final class AgentCLITests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testParse() {
        XCTAssertNil(AgentCLI.parse(arguments: ["/x/wisp-agent"]))
        XCTAssertNil(AgentCLI.parse(arguments: ["/x/wisp-agent", "--source", "codex"]))
        XCTAssertEqual(AgentCLI.parse(arguments: ["/x/wisp-agent", "status"]), .status(json: false))
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp"]), .help)
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp", "status", "--json"]), .status(json: true))
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp", "spend", "--json"]), .spend(json: true))
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp", "watch"]), .watch)
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp", "-h"]), .help)
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp", "stats"]), .invalid("Unknown command: stats"))
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp", "status", "-v"]), .invalid("Unknown option: -v"))
        XCTAssertEqual(AgentCLI.parse(arguments: ["wisp", "watch", "--json"]), .invalid("Unknown option: --json"))
    }

    private func row(
        _ project: String, state: String = "working", tool: String? = nil, cost: Double? = 0.41, real: Bool = true
    ) -> AgentReport.Row {
        AgentReport.Row(
            id: "id", project: project, branch: "main", agent: "Claude Code", state: state, model: "Opus",
            contextPercent: 42.4, cost: cost, costIsReal: real, tool: tool, toolSeconds: tool == nil ? nil : 12,
            turnSeconds: 185, folder: nil)
    }

    func testTable() {
        let report = AgentReport(
            generated: now, hidden: nil,
            sessions: [row("wisp", tool: "Running npm test"), row("site", state: "done", cost: 2, real: false)],
            spend: nil)
        XCTAssertEqual(
            AgentCLI.table(report, width: 120),
            """
            PROJECT  BRANCH  AGENT   STATE    MODEL  CTX  COST    TOOL              TIME
            wisp     main    Claude  working  Opus   42%  $0.41   Running npm test  3m 05s
            site     main    Claude  done     Opus   42%  ~$2.00  -                 3m 05s

            """)
    }

    func testTableShrinksToolThenProjectToFit() {
        let report = AgentReport(
            generated: now, hidden: nil,
            sessions: [row("a-very-long-project-name", tool: "Running a fairly long command line here")], spend: nil)
        let lines = AgentCLI.table(report, width: 80).split(separator: "\n")
        XCTAssertTrue(lines.allSatisfy { $0.count <= 80 }, "\(lines)")
        XCTAssertTrue(lines[1].contains("…"))
    }

    func testEmptyAndHidden() {
        let empty = AgentReport(generated: now, hidden: "during a call", sessions: [], spend: nil)
        XCTAssertEqual(AgentCLI.table(empty, width: 100), "No live sessions.\n\nDetails hidden during a call.\n")
    }

    func testSpend() {
        let report = AgentReport(
            generated: now, hidden: nil, sessions: [],
            spend: AgentReport.Spend(
                today: 1.25, week: 8, days: [0, 1, 2, 0, 4, 0, 1],
                projects: [
                    AgentReport.Project(project: "wisp", today: 1, week: 6),
                    AgentReport.Project(project: DailySpend.otherProjects, today: 0.25, week: 2),
                ]))
        XCTAssertEqual(
            AgentCLI.spend(report),
            """
            Today   ~$1.25
            7 days  ~$8.00  ▁▃▅▁█▁▃

            PROJECT         TODAY   7 DAYS
            wisp            ~$1.00  ~$6.00
            Other projects  ~$0.25  ~$2.00

            """)
    }

    func testSpendWithNothingYet() {
        let report = AgentReport(
            generated: now, hidden: nil, sessions: [],
            spend: AgentReport.Spend(today: 0, week: 0, days: Array(repeating: 0, count: 7), projects: []))
        XCTAssertEqual(AgentCLI.spend(report), "Today   ~$0.00\n7 days  ~$0.00  ▁▁▁▁▁▁▁\n")
    }
}

final class CommandLineToolTests: XCTestCase {
    private let helper = "/Applications/Wisp.app/Contents/MacOS/wisp-agent"

    func testStates() {
        XCTAssertEqual(CommandLineTool.state(exists: false, linkTarget: nil, helper: helper), .notInstalled)
        XCTAssertEqual(CommandLineTool.state(exists: true, linkTarget: helper, helper: helper), .installed)
        let dev = "/Users/me/wisp/build/Wisp.app/Contents/MacOS/wisp-agent"
        XCTAssertEqual(CommandLineTool.state(exists: true, linkTarget: dev, helper: helper), .otherApp(dev))
        XCTAssertEqual(CommandLineTool.state(exists: true, linkTarget: nil, helper: helper), .foreign)
        XCTAssertEqual(
            CommandLineTool.state(exists: true, linkTarget: "/opt/homebrew/bin/wisp", helper: helper), .foreign)
        // A dangling link of ours (the app was moved) is still ours to replace.
        XCTAssertEqual(
            CommandLineTool.state(exists: false, linkTarget: "/Old/Wisp.app/Contents/MacOS/wisp-agent", helper: helper),
            .otherApp("/Old/Wisp.app/Contents/MacOS/wisp-agent"))
    }

    func testOnPath() {
        let home = "/Users/me"
        XCTAssertTrue(CommandLineTool.isOnPath("/usr/bin:/Users/me/.local/bin", home: home))
        XCTAssertTrue(CommandLineTool.isOnPath("/Users/me/.local/bin/:/usr/bin", home: home))
        XCTAssertTrue(CommandLineTool.isOnPath("~/.local/bin", home: home))
        XCTAssertTrue(CommandLineTool.isOnPath("$HOME/.local/bin", home: home))
        XCTAssertFalse(CommandLineTool.isOnPath("/usr/bin:/Users/me/.local/binx", home: home))
        XCTAssertFalse(CommandLineTool.isOnPath("", home: home))
    }

    func testPathFromNoisyShellOutput() {
        XCTAssertEqual(
            CommandLineTool.path(fromShellOutput: "Welcome!\n<<wisp-path>>/usr/bin:/bin<</wisp-path>>\n"),
            "/usr/bin:/bin")
        XCTAssertNil(CommandLineTool.path(fromShellOutput: "no markers"))
        XCTAssertEqual(CommandLineTool.printPathCommand, #"printf '<<wisp-path>>%s<</wisp-path>>' "$PATH""#)
    }
}
