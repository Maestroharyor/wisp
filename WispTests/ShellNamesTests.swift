import XCTest

@testable import WispCore

final class ShellNamesTests: XCTestCase {
    private let added = ["tcsh", "csh", "ksh", "nu", "pwsh", "xonsh"]

    func testTheListCoversCommonShells() {
        for name in ["sh", "bash", "zsh", "dash", "fish"] + added {
            XCTAssertTrue(ShellNames.all.contains(name), name)
        }
    }

    func testTheOwnerWalkSkipsEveryShell() {
        for name in added {
            let table: [Int32: AgentProcess.Info] = [
                40: AgentProcess.Info(parent: 30, name: name, started: 4),
                30: AgentProcess.Info(parent: 1, name: "claude", started: 3),
            ]
            XCTAssertEqual(AgentProcess.owner(from: 40) { table[$0] }, AgentProcess(pid: 30, started: 3), name)
        }
    }

    func testALoginShellIsSkippedToo() {
        let table: [Int32: AgentProcess.Info] = [
            40: AgentProcess.Info(parent: 30, name: "-tcsh", started: 4),
            30: AgentProcess.Info(parent: 1, name: "codex", started: 3),
        ]
        XCTAssertEqual(AgentProcess.owner(from: 40) { table[$0] }, AgentProcess(pid: 30, started: 3))
    }

    func testXonshRunningAsPythonIsAShell() {
        XCTAssertTrue(
            ShellNames.isShell(name: "Python", arguments: ["/opt/homebrew/bin/python3", "/opt/homebrew/bin/xonsh"]))
        XCTAssertTrue(
            ShellNames.isShell(name: "python3.12", arguments: ["python3.12", "-u", "/Users/me/.local/bin/xonsh"]))
        XCTAssertTrue(ShellNames.isShell(name: "python3", arguments: ["python3", "-m", "xonsh", "-c", "ls"]))
        XCTAssertTrue(ShellNames.isShell(name: "Python", arguments: ["python", "/usr/local/bin/xonsh.py"]))
        // Other Python programs aren't shells, and only Python counts as xonsh's launcher.
        XCTAssertFalse(ShellNames.isShell(name: "Python", arguments: ["python3", "/Users/me/.local/bin/aider"]))
        XCTAssertFalse(ShellNames.isShell(name: "python3", arguments: ["python3", "-m", "http.server"]))
        XCTAssertFalse(ShellNames.isShell(name: "python3", arguments: ["python3", "-c", "import xonsh"]))
        XCTAssertFalse(ShellNames.isShell(name: "node", arguments: ["node", "/usr/local/bin/xonsh"]))
        XCTAssertFalse(ShellNames.isShell(name: "Python", arguments: nil))
        XCTAssertTrue(ShellNames.isShell(name: "-zsh", arguments: nil))
        XCTAssertFalse(ShellNames.isShell(name: "claude", arguments: nil))
    }

    func testTheOwnerWalkSkipsXonshRunningAsPython() {
        let table: [Int32: AgentProcess.Info] = [
            40: AgentProcess.Info(parent: 30, name: "Python", started: 4),
            30: AgentProcess.Info(parent: 1, name: "claude", started: 3),
        ]
        let arguments: [Int32: [String]] = [40: ["python3", "/opt/homebrew/bin/xonsh"]]
        XCTAssertEqual(
            AgentProcess.owner(from: 40, info: { table[$0] }, arguments: { arguments[$0] }),
            AgentProcess(pid: 30, started: 3))
        // Without its arguments it's taken for the agent, as before.
        XCTAssertEqual(AgentProcess.owner(from: 40) { table[$0] }, AgentProcess(pid: 40, started: 4))
    }

    func testARuleNeverWidensPastAShell() {
        for name in added {
            let command = "\(name) -c 'echo hi'"
            let rules = PermissionRule.suggest(
                tool: "Bash", input: .object(["command": .string(command)]), cwd: "/Users/me/app")
            XCTAssertEqual(rules, ["Bash(\(command))"], name)
        }
    }
}
