import XCTest

@testable import WispCore

final class IntegrationStatusTests: XCTestCase {
    func testStateFollowsTheHooksAndWhetherASessionWasSeen() {
        XCTAssertEqual(IntegrationStatus(link: .none, sessionSeen: false), .notInstalled)
        XCTAssertEqual(IntegrationStatus(link: .this, sessionSeen: false), .ready)
        XCTAssertEqual(IntegrationStatus(link: .this, sessionSeen: true), .connected)
        XCTAssertEqual(IntegrationStatus(link: .outdated, sessionSeen: true), .needsUpdate)
        XCTAssertEqual(IntegrationStatus(link: .other, sessionSeen: false), .otherCopy)
        // An agent Wisp only watches by its process has no hooks to install.
        XCTAssertEqual(IntegrationStatus(link: .none, sessionSeen: true, processOnly: true), .monitor)
    }

    func testLabels() {
        XCTAssertEqual(IntegrationStatus.connected.label, "Connected")
        XCTAssertEqual(IntegrationStatus.ready.label, "Ready")
        XCTAssertEqual(IntegrationStatus.needsUpdate.label, "Needs update")
        XCTAssertEqual(IntegrationStatus.monitor.label, "Monitor")
        XCTAssertEqual(IntegrationStatus.notInstalled.label, "Not installed")
        XCTAssertEqual(IntegrationStatus.otherCopy.label, "Another Wisp")
    }

    func testActionsForEachState() {
        XCTAssertEqual(IntegrationStatus.notInstalled.actions, [.install])
        XCTAssertEqual(IntegrationStatus.needsUpdate.actions, [.update, .remove])
        XCTAssertEqual(IntegrationStatus.ready.actions, [.repair, .remove])
        XCTAssertEqual(IntegrationStatus.connected.actions, [.repair, .remove])
        XCTAssertEqual(IntegrationStatus.otherCopy.actions, [.useHere, .remove])
        XCTAssertEqual(IntegrationStatus.monitor.actions, [])
        XCTAssertEqual(IntegrationStatus.Action.useHere.title, "Use this Wisp")
        XCTAssertEqual(IntegrationStatus.Action.repair.title, "Repair")
    }

    func testCapabilityWordsComeFromTheAdapter() {
        XCTAssertEqual(
            IntegrationStatus.capabilities(AgentSource.claude.adapter),
            ["context", "lifecycle", "tools", "approve", "answer", "jump"])
        XCTAssertEqual(
            IntegrationStatus.capabilities(AgentSource.codex.adapter),
            ["context", "lifecycle", "tools", "approve", "jump"])
        XCTAssertEqual(IntegrationStatus.capabilities(AgentSource.gemini.adapter), ["lifecycle", "tools", "jump"])
        XCTAssertEqual(
            IntegrationStatus.capabilities(AgentSource.qwen.adapter), ["lifecycle", "tools", "approve", "jump"])
        XCTAssertEqual(IntegrationStatus.capabilities(AgentSource.vibe.adapter), ["lifecycle", "tools", "jump"])
        XCTAssertEqual(IntegrationStatus.monitorCapabilities, ["running", "jump"])
    }
}
