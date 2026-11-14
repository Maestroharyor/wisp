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

    func testARuleNeverWidensPastAShell() {
        for name in added {
            let command = "\(name) -c 'echo hi'"
            let rules = PermissionRule.suggest(
                tool: "Bash", input: .object(["command": .string(command)]), cwd: "/Users/me/app")
            XCTAssertEqual(rules, ["Bash(\(command))"], name)
        }
    }
}
