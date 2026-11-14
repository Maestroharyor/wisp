import XCTest

@testable import WispCore

final class ContextThresholdsTests: XCTestCase {
    func testDefaultsAreSeventyAndNinety() {
        XCTAssertEqual(ContextUsage.Thresholds.standard.warn, 70)
        XCTAssertEqual(ContextUsage.Thresholds.standard.critical, 90)
    }

    func testLevelsFollowTheThresholds() {
        let thresholds = ContextUsage.Thresholds(warn: 60, critical: 80)
        XCTAssertEqual(ContextUsage.level(59.9, thresholds: thresholds), .normal)
        XCTAssertEqual(ContextUsage.level(60, thresholds: thresholds), .warning)
        XCTAssertEqual(ContextUsage.level(79.9, thresholds: thresholds), .warning)
        XCTAssertEqual(ContextUsage.level(80, thresholds: thresholds), .critical)
    }

    func testCriticalIsAlwaysAboveWarn() {
        let same = ContextUsage.Thresholds(warn: 80, critical: 80)
        XCTAssertGreaterThan(same.critical, same.warn)
        let below = ContextUsage.Thresholds(warn: 85, critical: 60)
        XCTAssertEqual(below.warn, 85)
        XCTAssertEqual(below.critical, 90)
        // The highest warn still leaves room for critical.
        let top = ContextUsage.Thresholds(warn: 100, critical: 100)
        XCTAssertEqual(top.warn, 95)
        XCTAssertEqual(top.critical, 100)
    }

    func testWarnStaysInRange() {
        XCTAssertEqual(ContextUsage.Thresholds(warn: 10, critical: 90).warn, 50)
        XCTAssertEqual(ContextUsage.Thresholds(warn: 10, critical: 90).critical, 90)
        XCTAssertEqual(ContextUsage.Thresholds(warn: 70, critical: 140).critical, 100)
    }

    func testTheTerminalBarUsesTheSameThresholds() {
        let thresholds = ContextUsage.Thresholds(warn: 60, critical: 80)
        XCTAssertEqual(StatusBarRenderer.contextColor(65), 105)
        XCTAssertEqual(StatusBarRenderer.contextColor(65, thresholds: thresholds), 214)
        XCTAssertEqual(StatusBarRenderer.contextColor(85, thresholds: thresholds), 203)
        let input = StatusBarRenderer.Input(project: "api", contextPercent: 85, thresholds: thresholds)
        XCTAssertTrue(StatusBarRenderer.line(input, columns: nil).contains { $0.color == 203 })
    }

    func testAnOldAlertSettingBecomesWarn() {
        // The alert used to have its own percentage; it now fires at warn.
        XCTAssertEqual(ContextUsage.Thresholds.migrated(alertAt: 80, warn: nil, critical: nil).warn, 80)
        XCTAssertEqual(ContextUsage.Thresholds.migrated(alertAt: 80, warn: nil, critical: nil).critical, 90)
        XCTAssertEqual(ContextUsage.Thresholds.migrated(alertAt: 95, warn: nil, critical: nil).critical, 100)
        // Once warn is set, the old value no longer counts.
        XCTAssertEqual(ContextUsage.Thresholds.migrated(alertAt: 80, warn: 65, critical: 85).warn, 65)
        XCTAssertEqual(ContextUsage.Thresholds.migrated(alertAt: nil, warn: nil, critical: nil), .standard)
    }

    func testStoredSettingsAreReadByKey() {
        let legacy: [String: Double] = ["contextThreshold": 85]
        XCTAssertEqual(ContextUsage.Thresholds.stored { legacy[$0] }, ContextUsage.Thresholds(warn: 85, critical: 90))
        let current: [String: Double] = [
            "contextThreshold": 85, "contextWarnPercent": 60, "contextCriticalPercent": 75,
        ]
        XCTAssertEqual(ContextUsage.Thresholds.stored { current[$0] }, ContextUsage.Thresholds(warn: 60, critical: 75))
        XCTAssertEqual(ContextUsage.Thresholds.stored { _ in nil }, .standard)
    }
}
