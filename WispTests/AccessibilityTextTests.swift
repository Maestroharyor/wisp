import XCTest

@testable import WispCore

final class AccessibilityTextTests: XCTestCase {
    func testDurationsAreSpokenInWords() {
        XCTAssertEqual(AccessibilityText.duration(401), "6 minutes 41 seconds")
        XCTAssertEqual(AccessibilityText.duration(60), "1 minute")
        XCTAssertEqual(AccessibilityText.duration(1), "1 second")
        XCTAssertEqual(AccessibilityText.duration(3_725), "1 hour 2 minutes")
        XCTAssertEqual(AccessibilityText.duration(0), "0 seconds")
        XCTAssertEqual(AccessibilityText.duration(-5), "0 seconds")
    }

    func testATimerSaysWhatsLeft() {
        XCTAssertEqual(AccessibilityText.timer(label: "Tea", remaining: 401), "Tea, 6 minutes 41 seconds left")
        XCTAssertEqual(AccessibilityText.timer(label: "", remaining: 30), "Timer, 30 seconds left")
    }

    func testBatterySaysLowAndCharging() {
        XCTAssertEqual(AccessibilityText.battery(percent: 18, charging: false, low: true), "Battery 18%, low")
        XCTAssertEqual(AccessibilityText.battery(percent: 64, charging: true, low: false), "Battery 64%, charging")
        XCTAssertEqual(AccessibilityText.battery(percent: 90, charging: false, low: false), "Battery 90%")
    }

    func testALevelSaysItsPercentOrMuted() {
        XCTAssertEqual(AccessibilityText.level(name: "Volume", value: 0.5, muted: false), "Volume 50%")
        XCTAssertEqual(AccessibilityText.level(name: "Volume", value: 0.5, muted: true), "Volume muted")
    }

    func testAnAgentSaysWhoWhereWhatAndContext() {
        XCTAssertEqual(
            AccessibilityText.agent(name: "Claude Code", project: "wisp", state: "Working", context: 0.23),
            "Claude Code in wisp, working, 23% context")
        XCTAssertEqual(
            AccessibilityText.agent(name: "Codex", project: nil, state: "Ready", context: nil), "Codex, ready")
    }

    func testAContextWarningIsSpokenNotOnlyColoured() {
        XCTAssertEqual(
            AccessibilityText.agent(
                name: "Claude Code", project: "wisp", state: "Working", context: 0.92, warning: true),
            "Claude Code in wisp, working, 92% context, running low")
    }

    func testSecondaryTextIsStrongerWithIncreaseContrast() {
        XCTAssertEqual(ContrastStyle.secondaryOpacity(increased: false), 0.55)
        XCTAssertGreaterThanOrEqual(ContrastStyle.secondaryOpacity(increased: true), 0.8)
    }

    func testTheSmallestClickTarget() {
        XCTAssertEqual(ContrastStyle.minimumTarget, 24)
    }
}
