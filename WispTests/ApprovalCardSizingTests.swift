import CoreGraphics
import XCTest

@testable import WispCore

final class ApprovalCardSizingTests: XCTestCase {
    func testAPlainRequestKeepsRoomForItsActionRow() {
        XCTAssertEqual(
            SurfaceSizing.approvalCardExtra(previewOpen: false, inlineDiff: false),
            SurfaceSizing.approvalActionRowHeight)
    }

    func testAnInlineDiffAddsItsLinesUnderTheActions() {
        XCTAssertEqual(
            SurfaceSizing.approvalCardExtra(previewOpen: false, inlineDiff: true),
            SurfaceSizing.approvalActionRowHeight + SurfaceSizing.inlineDiffHeight)
    }

    func testAnOpenPreviewReplacesTheInlineDiff() {
        let open = SurfaceSizing.approvalActionRowHeight + SurfaceSizing.approvalPreviewHeight
        XCTAssertEqual(SurfaceSizing.approvalCardExtra(previewOpen: true, inlineDiff: false), open)
        XCTAssertEqual(SurfaceSizing.approvalCardExtra(previewOpen: true, inlineDiff: true), open)
    }

    func testOpeningThePreviewGrowsTheCard() {
        let layout = NotchGeometry.layout(
            for: ScreenMetrics(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                safeAreaTop: 32,
                auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
                auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
            ))
        let closed = SurfaceSizing.rect(
            for: .notification(extra: SurfaceSizing.approvalCardExtra(previewOpen: false, inlineDiff: true)),
            in: layout)
        let open = SurfaceSizing.rect(
            for: .notification(extra: SurfaceSizing.approvalCardExtra(previewOpen: true, inlineDiff: true)),
            in: layout)
        XCTAssertGreaterThan(open.height, closed.height)
        XCTAssertEqual(open.width, closed.width)
    }

    func testTheActionRowHoldsTheButtons() {
        // Deny, Allow All, the ellipsis and Allow are 28 pt tall; the row leaves a gap above them.
        XCTAssertGreaterThanOrEqual(SurfaceSizing.approvalActionRowHeight, 28 + 8)
    }
}
