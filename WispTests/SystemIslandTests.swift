import CoreGraphics
import XCTest

@testable import WispCore

final class SystemIslandTests: XCTestCase {
    func testTheSettingOverridesDetection() {
        XCTAssertTrue(SystemIsland.present(setting: .yes, modelIdentifier: "Mac14,6", builtIn: true))
        XCTAssertFalse(SystemIsland.present(setting: .no, modelIdentifier: "Mac14,6", builtIn: true))
    }

    func testAnUnknownModelHasNoIsland() {
        XCTAssertFalse(SystemIsland.present(setting: .automatic, modelIdentifier: "Mac14,6", builtIn: true))
        XCTAssertFalse(SystemIsland.present(setting: .automatic, modelIdentifier: nil, builtIn: true))
    }

    func testAKnownModelHasAnIslandOnlyOnItsOwnDisplay() {
        let known: Set<String> = ["Test1,1"]
        XCTAssertTrue(
            SystemIsland.present(setting: .automatic, modelIdentifier: "Test1,1", builtIn: true, known: known))
        XCTAssertFalse(
            SystemIsland.present(setting: .automatic, modelIdentifier: "Test1,1", builtIn: false, known: known))
    }

    func testExternalDisplaysNeverHaveOne() {
        XCTAssertFalse(SystemIsland.present(setting: .yes, modelIdentifier: nil, builtIn: false))
    }

    func testTopCentreMovesOutOfTheIslandsWay() {
        XCTAssertEqual(Placement.top.clear(ofSystemIsland: true), .topRight)
        XCTAssertEqual(Placement.top.clear(ofSystemIsland: false), .top)
        for placement in Placement.allCases where placement != .top {
            XCTAssertEqual(placement.clear(ofSystemIsland: true), placement)
        }
    }

    func testTheReportListsWhatDetectionNeeds() {
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaTop: 38,
            auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 692, height: 38),
            auxiliaryTopRight: CGRect(x: 820, y: 944, width: 692, height: 38))
        let report = SystemIsland.report(modelIdentifier: "Mac14,6", builtIn: true, metrics: metrics)
        XCTAssertTrue(report.contains("Model: Mac14,6"))
        XCTAssertTrue(report.contains("Built in: yes"))
        XCTAssertTrue(report.contains("Safe area top: 38"))
        XCTAssertTrue(report.contains("Left of camera: 0, 944, 692 × 38"))
        XCTAssertTrue(report.contains("Right of camera: 820, 944, 692 × 38"))
        XCTAssertTrue(report.contains("Frame: 0, 0, 1512 × 982"))
        XCTAssertTrue(report.contains("Visible: 0, 0, 1512 × 944"))
    }

    func testTheReportSaysWhenThereIsNoHousing() {
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        let report = SystemIsland.report(modelIdentifier: nil, builtIn: false, metrics: metrics)
        XCTAssertTrue(report.contains("Model: unknown"))
        XCTAssertTrue(report.contains("Left of camera: none"))
    }
}
