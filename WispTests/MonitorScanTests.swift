import XCTest

@testable import WispCore

final class MonitorScanTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testScansWhileAViewShows() {
        var scan = MonitorScan()
        XCTAssertFalse(scan.wanted(tracking: false))
        scan.viewAppeared()
        XCTAssertTrue(scan.wanted(tracking: false))
        XCTAssertEqual(scan.tick(surfaceVisible: true, tracking: false, now: start), .scan)
        scan.viewDisappeared()
        XCTAssertFalse(scan.wanted(tracking: false))
        XCTAssertEqual(scan.tick(surfaceVisible: true, tracking: false, now: start), .stop)
    }

    func testAViewThatNeverSaidItLeftStopsOnceNothingShowsForAWhile() {
        var scan = MonitorScan()
        scan.viewAppeared()
        // The shelf and window closed but the view's onDisappear never came.
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: false, now: start), .wait)
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: false, now: start + 30), .wait)
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: false, now: start + MonitorScan.grace), .stop)
        XCTAssertFalse(scan.wanted(tracking: false))
        // The next view to appear starts it again.
        scan.viewAppeared()
        XCTAssertEqual(scan.tick(surfaceVisible: true, tracking: false, now: start + 200), .scan)
    }

    func testShowingAgainResetsTheWait() {
        var scan = MonitorScan()
        scan.viewAppeared()
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: false, now: start), .wait)
        XCTAssertEqual(scan.tick(surfaceVisible: true, tracking: false, now: start + 50), .scan)
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: false, now: start + 60), .wait)
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: false, now: start + 100), .wait)
    }

    func testAnAgentStillRunningKeepsItScanningUnseen() {
        var scan = MonitorScan()
        XCTAssertTrue(scan.wanted(tracking: true))
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: true, now: start), .scan)
        XCTAssertEqual(scan.tick(surfaceVisible: false, tracking: false, now: start + 15), .stop)
    }

    func testTheCountNeverGoesBelowZero() {
        var scan = MonitorScan()
        scan.viewDisappeared()
        scan.viewAppeared()
        XCTAssertTrue(scan.wanted(tracking: false))
    }
}
