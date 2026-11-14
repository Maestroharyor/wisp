import CoreGraphics
import XCTest

@testable import WispCore

final class QuestionRowsTests: XCTestCase {
    func testOptionsThatFitStayOnOneRow() {
        XCTAssertEqual(SurfaceSizing.questionRows(options: [80, 90, 60], width: 300), 1)
        // Exactly full: 80 + 6 + 90 + 6 + 118 = 300.
        XCTAssertEqual(SurfaceSizing.questionRows(options: [80, 90, 118], width: 300), 1)
    }

    func testOptionsWrapOntoMoreRows() {
        XCTAssertEqual(SurfaceSizing.questionRows(options: [80, 90, 119], width: 300), 2)
        XCTAssertEqual(SurfaceSizing.questionRows(options: [200, 200, 200, 200], width: 300), 4)
    }

    func testAnOptionWiderThanTheRowTakesARowOfItsOwn() {
        XCTAssertEqual(SurfaceSizing.questionRows(options: [50, 400, 50], width: 300), 3)
    }

    func testFlowRowsListWhatGoesOnEachRow() {
        XCTAssertEqual(SurfaceSizing.flowRows([80, 90, 119, 20], width: 300, spacing: 6), [[0, 1], [2, 3]])
        XCTAssertEqual(SurfaceSizing.flowRows([], width: 300, spacing: 6), [])
    }

    func testNoOptionsIsOneRow() {
        XCTAssertEqual(SurfaceSizing.questionRows(options: [], width: 300), 1)
        XCTAssertEqual(SurfaceSizing.questionRows(options: [50], width: 0), 1)
    }

    func testTheRowGrowsToThreeRowsAtMost() {
        XCTAssertEqual(SurfaceSizing.questionRowHeight(rows: 1), SurfaceSizing.questionRowHeight)
        XCTAssertEqual(SurfaceSizing.questionRowHeight(rows: 0), SurfaceSizing.questionRowHeight)
        XCTAssertEqual(SurfaceSizing.questionRowHeight(rows: 2), 40 + 34)
        XCTAssertEqual(SurfaceSizing.questionRowHeight(rows: 3), 40 + 68)
        XCTAssertEqual(SurfaceSizing.questionRowHeight(rows: 7), SurfaceSizing.questionRowHeight(rows: 3))
    }
}
