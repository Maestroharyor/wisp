import XCTest

@testable import WispCore

final class StatusLineSnapshotTests: XCTestCase {
    func testDecodesTheDocumentedFields() {
        let snapshot = StatusLineSnapshot.decode(
            Data(
                """
                {"session_id":"abc","cwd":"/ignored","transcript_path":"/t.jsonl",
                 "model":{"id":"claude-opus-4-1","display_name":"Opus"},
                 "workspace":{"current_dir":"/Users/me/code/wisp","project_dir":"/Users/me/code/wisp"},
                 "cost":{"total_cost_usd":0.4123,"total_duration_ms":45000,"total_api_duration_ms":2300,
                         "total_lines_added":120,"total_lines_removed":34},
                 "context_window":{"used_percentage":78.4,"context_window_size":200000,
                                   "current_usage":{"input_tokens":10,"cache_read_input_tokens":5}},
                 "worktree":{"name":"x","branch":"feature/bar"}}
                """.utf8))
        XCTAssertEqual(snapshot.sessionID, "abc")
        XCTAssertEqual(snapshot.cwd, "/Users/me/code/wisp")
        XCTAssertEqual(snapshot.project, "wisp")
        XCTAssertEqual(snapshot.transcriptPath, "/t.jsonl")
        XCTAssertEqual(snapshot.model, "Opus")
        XCTAssertEqual(snapshot.cost, 0.4123)
        XCTAssertEqual(snapshot.duration, 45)
        XCTAssertEqual(snapshot.apiDuration, 2.3)
        XCTAssertEqual(snapshot.linesAdded, 120)
        XCTAssertEqual(snapshot.linesRemoved, 34)
        XCTAssertEqual(snapshot.contextPercent, 78.4)
        XCTAssertEqual(snapshot.contextSize, 200_000)
        XCTAssertEqual(snapshot.branch, "feature/bar")
    }

    func testNullAndMissingFieldsAreNil() {
        let snapshot = StatusLineSnapshot.decode(
            Data(
                #"{"session_id":"s","cwd":"/a/b","context_window":{"used_percentage":null,"current_usage":null}}"#.utf8)
        )
        XCTAssertEqual(snapshot.cwd, "/a/b")
        XCTAssertNil(snapshot.contextPercent)
        XCTAssertNil(snapshot.cost)
        XCTAssertNil(snapshot.model)
        XCTAssertNil(snapshot.branch)
    }

    func testInputThatIsNotJSONGivesAnEmptySnapshot() {
        let snapshot = StatusLineSnapshot.decode(Data("nope".utf8))
        XCTAssertNil(snapshot.sessionID)
        XCTAssertEqual(snapshot.project, "Claude")
    }

    func testPercentIsClamped() {
        let snapshot = StatusLineSnapshot.decode(Data(#"{"context_window":{"used_percentage":130}}"#.utf8))
        XCTAssertEqual(snapshot.contextPercent, 100)
    }
}

final class ContextUsageTests: XCTestCase {
    func testTheNoticeFitsThePill() {
        XCTAssertEqual(ContextUsage.notice(percent: 85.6, project: "api"), "86% · api")
    }

    func testLevels() {
        XCTAssertEqual(ContextUsage.level(0), .normal)
        XCTAssertEqual(ContextUsage.level(69.9), .normal)
        XCTAssertEqual(ContextUsage.level(70), .warning)
        XCTAssertEqual(ContextUsage.level(89.9), .warning)
        XCTAssertEqual(ContextUsage.level(90), .critical)
    }

    func testAlertFiresOnceAndRearmsBelowTheThreshold() {
        var alerted = false
        var fired: [Bool] = []
        for percent in [50.0, 81, 85, 90, 40, 82] {
            let result = ContextUsage.alert(percent: percent, threshold: 80, alerted: alerted)
            fired.append(result.fire)
            alerted = result.alerted
        }
        XCTAssertEqual(fired, [false, true, false, false, false, true])
    }

    func testUnknownPercentChangesNothing() {
        XCTAssertEqual(ContextUsage.alert(percent: nil, threshold: 80, alerted: true).alerted, true)
        XCTAssertEqual(ContextUsage.alert(percent: nil, threshold: 80, alerted: false).fire, false)
    }
}

final class GitHeadTests: XCTestCase {
    func testBranchFromHead() {
        XCTAssertEqual(GitHead.branch(fromHead: "ref: refs/heads/main\n"), "main")
        XCTAssertEqual(GitHead.branch(fromHead: "ref: refs/heads/feat/agent-bar"), "feat/agent-bar")
        XCTAssertEqual(GitHead.branch(fromHead: "1340fab0123456789abcdef0123456789abcdef0\n"), "1340fab")
        XCTAssertNil(GitHead.branch(fromHead: "garbage"))
        XCTAssertNil(GitHead.branch(fromHead: "ref: "))
    }

    func testGitDirectoryFromDotGitFile() {
        XCTAssertEqual(
            GitHead.gitDirectory(fromDotGit: "gitdir: /repo/.git/worktrees/wt\n", in: "/wt"), "/repo/.git/worktrees/wt")
        XCTAssertEqual(
            GitHead.gitDirectory(fromDotGit: "gitdir: ../.git/modules/sub", in: "/repo/sub"),
            "/repo/sub/../.git/modules/sub")
        XCTAssertNil(GitHead.gitDirectory(fromDotGit: "nothing", in: "/x"))
    }

    func testWalksUpToTheRepository() {
        let files = ["/repo/.git/HEAD": "ref: refs/heads/main"]
        XCTAssertEqual(GitHead.branch(cwd: "/repo/Sources/App", read: { files[$0] }), "main")
    }

    func testFollowsAWorktreeFile() {
        let files = [
            "/wt/.git": "gitdir: /repo/.git/worktrees/wt",
            "/repo/.git/worktrees/wt/HEAD": "ref: refs/heads/fix/thing",
        ]
        XCTAssertEqual(GitHead.branch(cwd: "/wt/sub", read: { files[$0] }), "fix/thing")
    }

    func testOutsideARepositoryIsNil() {
        XCTAssertNil(GitHead.branch(cwd: "/tmp/x", read: { _ in nil }))
        XCTAssertNil(GitHead.branch(cwd: "relative", read: { _ in "ref: refs/heads/main" }))
    }
}

final class StatusBarRendererTests: XCTestCase {
    private let full = StatusBarRenderer.Input(
        project: "wisp", branch: "main", contextPercent: 78, model: "Opus", cost: 0.41, linesAdded: 120,
        linesRemoved: 34)

    func testPlainFullLine() {
        XCTAssertEqual(
            StatusBarRenderer.render(full, columns: nil, color: false),
            "◆ wisp  main  ▕████████░░▏ 78%  Opus  $0.41  +120 −34")
    }

    func testDropsSegmentsFromTheRightWhenNarrow() {
        XCTAssertEqual(
            StatusBarRenderer.render(full, columns: 40, color: false), "◆ wisp  main  ▕████████░░▏ 78%  Opus")
        XCTAssertEqual(StatusBarRenderer.render(full, columns: 12, color: false), "◆ wisp  main")
        XCTAssertEqual(StatusBarRenderer.render(full, columns: 4, color: false), "◆ w…")
    }

    func testOmitsUnknownSegments() {
        let bare = StatusBarRenderer.Input(project: "wisp")
        XCTAssertEqual(StatusBarRenderer.render(bare, columns: 80, color: false), "◆ wisp")
    }

    func testColourWrapsSpansWithCodes() {
        let line = StatusBarRenderer.render(full, columns: nil, color: true)
        XCTAssertTrue(line.contains("\u{1B}[38;5;214m▕████████░░▏ 78%\u{1B}[0m"))
        XCTAssertTrue(line.contains("\u{1B}[38;5;114m+120\u{1B}[0m"))
        XCTAssertEqual(line.components(separatedBy: "\u{1B}[0m").count - 1, 5)
    }

    func testContextColours() {
        XCTAssertEqual(StatusBarRenderer.contextColor(10), 105)
        XCTAssertEqual(StatusBarRenderer.contextColor(75), 214)
        XCTAssertEqual(StatusBarRenderer.contextColor(95), 203)
    }

    func testCostText() {
        XCTAssertEqual(StatusBarRenderer.costText(0), "$0.00")
        XCTAssertEqual(StatusBarRenderer.costText(12.345), "$12.35")
        XCTAssertEqual(StatusBarRenderer.costText(150.4), "$150")
    }

    func testProjectColourIsInTheCube() {
        for hue in ProjectColor.palette {
            XCTAssertTrue((16...231).contains(StatusBarRenderer.cubeColor(hue: hue)))
        }
        XCTAssertEqual(StatusBarRenderer.cubeColor(hue: 0), 16 + 36 * 5 + 6 * 3 + 3)
    }

    func testSnapshotBranchWinsOverHead() {
        let input = StatusBarRenderer.Input(snapshot: StatusLineSnapshot(cwd: "/a/wisp", branch: "wt"), branch: "main")
        XCTAssertEqual(input.branch, "wt")
        XCTAssertEqual(input.project, "wisp")
    }

    func testXtermCodesToRGB() {
        XCTAssertTrue(StatusBarRenderer.rgb(code: 16) == (0, 0, 0))
        XCTAssertTrue(StatusBarRenderer.rgb(code: 231) == (1, 1, 1))
        let amber = StatusBarRenderer.rgb(code: 214)
        XCTAssertEqual(amber.red, 1)
        XCTAssertEqual(amber.green, 175.0 / 255)
        XCTAssertEqual(amber.blue, 0)
        XCTAssertEqual(StatusBarRenderer.rgb(code: 245).red, 138.0 / 255)
        XCTAssertTrue(StatusBarRenderer.rgb(code: 3) == (0.5, 0.5, 0.5))
    }

    func testBarHonoursTheEnvironment() {
        let snapshot = StatusLineSnapshot(cwd: "/a/wisp", model: "Opus", cost: 0.41, contextPercent: 78)
        XCTAssertEqual(
            StatusBarRenderer.bar(for: snapshot, branch: "main", environment: ["NO_COLOR": "1", "COLUMNS": "18"]),
            "◆ wisp  main")
        XCTAssertTrue(StatusBarRenderer.bar(for: snapshot, branch: nil, environment: [:]).contains("\u{1B}["))
        XCTAssertTrue(
            StatusBarRenderer.bar(for: snapshot, branch: nil, environment: ["NO_COLOR": ""]).contains("\u{1B}["),
            "an empty NO_COLOR doesn't count")
        XCTAssertEqual(
            StatusBarRenderer.bar(for: snapshot, branch: nil, environment: ["NO_COLOR": "1", "COLUMNS": "wide"]),
            "◆ wisp  ▕████████░░▏ 78%  Opus  $0.41")
    }
}
