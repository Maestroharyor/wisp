import XCTest

@testable import WispCore

final class DiagnosticsTests: XCTestCase {
    func testReportStartsWithVersionsAndTheIslandSetting() {
        let report = Diagnostics.report(
            appVersion: "0.1.15 (42)", systemVersion: "26.1.0", islandSetting: .automatic, displays: [])
        XCTAssertEqual(
            report.split(separator: "\n").map(String.init),
            ["Wisp 0.1.15 (42)", "macOS 26.1.0", "Dynamic Island detection: Automatic"])
    }

    func testEachDisplayGetsANumberedBlock() {
        let report = Diagnostics.report(
            appVersion: "1.0 (1)", systemVersion: "14.6.1", islandSetting: .yes,
            displays: ["Model: Mac14,6\nBuilt in: yes", "Model: Mac14,6\nBuilt in: no"])
        XCTAssertTrue(report.contains("Dynamic Island detection: Has a Dynamic Island"))
        XCTAssertTrue(report.contains("\n\nDisplay 1\nModel: Mac14,6\nBuilt in: yes"))
        XCTAssertTrue(report.hasSuffix("\n\nDisplay 2\nModel: Mac14,6\nBuilt in: no"))
    }

    func testIslandSettingTitlesMatchThePicker() {
        XCTAssertEqual(IslandSetting.allCases.map(\.title), ["Automatic", "Has a Dynamic Island", "No Dynamic Island"])
    }
}
