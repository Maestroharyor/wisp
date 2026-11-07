import XCTest

@testable import WispCore

final class HookTimeoutTests: XCTestCase {
    private let helper = "/A/wisp-agent"
    private let claude = AgentSource.claude.adapter.hookFile
    private let codex = AgentSource.codex.adapter.hookFile

    func testTimeoutFromPushSetting() {
        XCTAssertEqual(HookInstaller.approvalTimeout(push: false, minutes: 10), 120)
        XCTAssertEqual(HookInstaller.approvalTimeout(push: true, minutes: 10), 600)
        XCTAssertEqual(HookInstaller.approvalTimeout(push: true, minutes: 0), 120)
        XCTAssertEqual(HookInstaller.approvalTimeout(push: true, minutes: 999), 3600)
    }

    func testDefaultCommandIsUnchanged() {
        XCTAssertEqual(HookInstaller.command(helper: helper, file: claude), "'/A/wisp-agent'")
        XCTAssertEqual(HookInstaller.command(helper: helper, file: claude, timeout: 120), "'/A/wisp-agent'")
        XCTAssertEqual(
            HookInstaller.command(helper: helper, file: claude, timeout: 600), "'/A/wisp-agent' --timeout 600")
        XCTAssertEqual(
            HookInstaller.command(helper: helper, file: codex, timeout: 600),
            "'/A/wisp-agent' --source codex --timeout 600")
    }

    func testHelperReadsTheFlag() {
        XCTAssertEqual(HookInstaller.timeout(arguments: ["wisp-agent", "--source", "codex", "--timeout", "600"]), 600)
        XCTAssertNil(HookInstaller.timeout(arguments: ["wisp-agent"]))
        XCTAssertNil(HookInstaller.timeout(arguments: ["wisp-agent", "--timeout"]))
        XCTAssertNil(HookInstaller.timeout(arguments: ["wisp-agent", "--timeout", "-5"]))
        XCTAssertNil(HookInstaller.timeout(arguments: ["wisp-agent", "--timeout", "soon"]))
    }

    private func installed(_ file: HookFile, timeout: Int) throws -> Data {
        try HookInstaller.install(
            into: Data(), command: HookInstaller.command(helper: helper, file: file, timeout: timeout), file: file,
            timeout: timeout)
    }

    func testTimeoutFlagIsNotACommand() {
        XCTAssertNil(AgentCLI.parse(arguments: ["/A/wisp-agent", "--timeout", "600"]))
        XCTAssertNil(AgentCLI.parse(arguments: ["/A/wisp-agent", "--source", "codex", "--timeout", "600"]))
    }

    func testInstallWritesTheTimeout() throws {
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: installed(claude, timeout: 600)), 600)
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: installed(codex, timeout: 120)), 120)
        XCTAssertNil(try HookInstaller.installedApprovalTimeout(in: Data("{}".utf8)))
    }

    func testChangedTimeoutReadsAsOutdatedNotAnotherCopy() throws {
        for file in [claude, codex] {
            let short = try installed(file, timeout: 120)
            let long = try installed(file, timeout: 600)
            XCTAssertEqual(try HookInstaller.link(in: short, helper: helper, file: file, timeout: 120), .this)
            XCTAssertEqual(try HookInstaller.link(in: short, helper: helper, file: file, timeout: 600), .outdated)
            XCTAssertEqual(try HookInstaller.link(in: long, helper: helper, file: file, timeout: 600), .this)
            XCTAssertEqual(try HookInstaller.link(in: long, helper: helper, file: file, timeout: 120), .outdated)
            XCTAssertEqual(try HookInstaller.link(in: long, helper: "/B/wisp-agent", file: file, timeout: 600), .other)
        }
    }

    func testReinstallReplacesTheOldTimeout() throws {
        let long = try installed(claude, timeout: 600)
        let back = try HookInstaller.install(
            into: long, command: HookInstaller.command(helper: helper, file: claude), file: claude)
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: back), 120)
        XCTAssertEqual(try HookInstaller.link(in: back, helper: helper, file: claude), .this)
    }
}
