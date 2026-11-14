import XCTest

@testable import WispCore

final class BashChildTests: XCTestCase {
    /// How Claude Code runs an allowed Bash call: a login shell's `-c` with the command inside `eval '…'`.
    private func shell(_ quoted: String) -> [String] {
        [
            "/bin/zsh", "-c",
            "source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh 2>/dev/null || true && eval '\(quoted)' "
                + "< /dev/null && pwd -P >| /var/folders/x/claude-1-cwd",
        ]
    }

    func testTheCommandComesFromTheInput() {
        XCTAssertEqual(BashChild.command(of: .object(["command": .string("git status")])), "git status")
        XCTAssertNil(BashChild.command(of: .object(["command": .string("   ")])))
        XCTAssertNil(BashChild.command(of: .object(["file_path": .string("/a")])))
        XCTAssertNil(BashChild.command(of: nil))
    }

    func testTheShellClaudeCodeStartsRunsTheCommand() {
        XCTAssertTrue(BashChild.runs("git status", arguments: shell("git status")))
        XCTAssertFalse(BashChild.runs("git diff", arguments: shell("git status")))
        // A shorter command that's part of the one running isn't it.
        XCTAssertFalse(BashChild.runs("git", arguments: shell("git status")))
    }

    func testSingleQuotesAreMatchedAsTheShellQuotesThem() {
        let command = "echo 'hi there' | tr ' ' '-'"
        let quoted = command.replacingOccurrences(of: "'", with: #"'"'"'"#)
        XCTAssertTrue(BashChild.runs(command, arguments: shell(quoted)))
        let older = command.replacingOccurrences(of: "'", with: #"'\''"#)
        XCTAssertTrue(BashChild.runs(command, arguments: shell(older)))
        XCTAssertFalse(BashChild.runs(command, arguments: shell(command)))
    }

    func testAnArgumentThatIsTheWholeCommandCounts() {
        XCTAssertTrue(BashChild.runs("npm test", arguments: ["/bin/bash", "-c", "npm test"]))
        XCTAssertFalse(BashChild.runs("npm test", arguments: ["/bin/bash", "-c", "npm test --watch"]))
    }

    func testOtherChildrenNeverMatch() {
        // The status line and hooks run Wisp's helper; their arguments don't hold the command.
        let helper = ["/bin/sh", "-c", "/Applications/Wisp.app/Contents/MacOS/wisp-agent statusline"]
        XCTAssertFalse(BashChild.runs("ls", arguments: helper))
        XCTAssertFalse(BashChild.runs("ls", arguments: []))
    }

    func testOnlyProcessesUnderTheAgentStartedSinceCount() {
        let table = [
            BashChild.Entry(pid: 10, parent: 1, started: 0),
            // The agent's shell for the call, and a wrapper's child under another child.
            BashChild.Entry(pid: 11, parent: 10, started: 105),
            BashChild.Entry(pid: 12, parent: 11, started: 106),
            // Started before the request: an older call.
            BashChild.Entry(pid: 13, parent: 10, started: 50),
            // Another process's child.
            BashChild.Entry(pid: 14, parent: 99, started: 110),
        ]
        XCTAssertEqual(BashChild.newDescendants(of: 10, in: table, since: 100), [11, 12])
        XCTAssertEqual(BashChild.newDescendants(of: 42, in: table, since: 100), [])
    }

    func testTheWalkIsBoundedOnALoop() {
        let table = [
            BashChild.Entry(pid: 11, parent: 12, started: 105),
            BashChild.Entry(pid: 12, parent: 11, started: 105),
        ]
        XCTAssertEqual(BashChild.newDescendants(of: 11, in: table, since: 100), [12])
    }
}
