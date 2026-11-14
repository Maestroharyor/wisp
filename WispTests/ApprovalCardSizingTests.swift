import CoreGraphics
import XCTest

@testable import WispCore

final class ApprovalCardSizingTests: XCTestCase {
    private let answers = SurfaceSizing.approvalQuietRowHeight + SurfaceSizing.approvalActionRowHeight

    private var layout: NotchLayout {
        NotchGeometry.layout(
            for: ScreenMetrics(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                safeAreaTop: 32,
                auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
                auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
            ))
    }

    func testAPlainRequestKeepsRoomForItsAnswerRows() {
        XCTAssertEqual(SurfaceSizing.approvalCardExtra(previewOpen: false, inlineDiffRows: 0), answers)
    }

    func testAnInlineDiffGrowsWithItsRows() {
        let two = SurfaceSizing.approvalCardExtra(previewOpen: false, inlineDiffRows: 2)
        let six = SurfaceSizing.approvalCardExtra(previewOpen: false, inlineDiffRows: 6)
        XCTAssertEqual(two, answers + SurfaceSizing.inlineDiffHeight(rows: 2))
        XCTAssertGreaterThan(six, two)
        // Rows past the most the card shows add nothing.
        XCTAssertEqual(SurfaceSizing.inlineDiffHeight(rows: 40), SurfaceSizing.inlineDiffHeight(rows: 6))
        XCTAssertEqual(SurfaceSizing.inlineDiffHeight(rows: 0), 0)
    }

    func testSixRowsFitTheirRowsAndCounts() {
        let rows = 6 * SurfaceSizing.inlineDiffRowHeight + 5 * SurfaceSizing.inlineDiffRowSpacing
        XCTAssertEqual(SurfaceSizing.inlineDiffHeight(rows: 6), rows + SurfaceSizing.inlineDiffChrome)
    }

    func testAnOpenPreviewReplacesTheInlineDiff() {
        let open = SurfaceSizing.approvalPreviewHeight + answers
        XCTAssertEqual(SurfaceSizing.approvalCardExtra(previewOpen: true, inlineDiffRows: 0), open)
        XCTAssertEqual(SurfaceSizing.approvalCardExtra(previewOpen: true, inlineDiffRows: 6), open)
    }

    func testOpeningThePreviewGrowsTheCard() {
        let closed = SurfaceSizing.rect(
            for: .notification(
                extra: SurfaceSizing.approvalCardExtra(previewOpen: false, inlineDiffRows: 6), wide: true),
            in: layout)
        let open = SurfaceSizing.rect(
            for: .notification(
                extra: SurfaceSizing.approvalCardExtra(previewOpen: true, inlineDiffRows: 6), wide: true),
            in: layout)
        XCTAssertGreaterThan(open.height, closed.height)
        XCTAssertEqual(open.width, closed.width)
    }

    func testACardWithADiffIsWider() {
        let plain = SurfaceSizing.rect(for: .notification(extra: answers), in: layout)
        let diff = SurfaceSizing.rect(for: .notification(extra: answers, wide: true), in: layout)
        XCTAssertEqual(plain.width, SurfaceSizing.notificationWidth)
        XCTAssertEqual(diff.width, SurfaceSizing.wideNotificationWidth)
        XCTAssertEqual(diff.width, 520)
    }

    func testTheAnswerRowsHoldTheirButtons() {
        // Deny and Allow are 32 pt tall with a margin under them; the quiet row's buttons are 22 pt.
        XCTAssertGreaterThanOrEqual(SurfaceSizing.approvalActionRowHeight, 32 + 8)
        XCTAssertGreaterThanOrEqual(SurfaceSizing.approvalQuietRowHeight, 22 + 4)
    }
}
