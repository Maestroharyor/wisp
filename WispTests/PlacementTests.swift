import CoreGraphics
import XCTest

@testable import WispCore

final class PlacementTests: XCTestCase {
    private let sizes = NotchSizes.standard

    // A 1080p display with a 24 pt menu bar and the Dock along the bottom (70 pt).
    private let docked = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 986)
    )

    // The same display with the Dock hidden.
    private let bare = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056)
    )

    // A 14" MacBook Pro with its camera housing.
    private let notched = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        safeAreaTop: 38,
        auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 692, height: 38),
        auxiliaryTopRight: CGRect(x: 820, y: 944, width: 692, height: 38)
    )

    private func layout(_ screen: ScreenMetrics, _ placement: Placement) -> NotchLayout {
        NotchGeometry.layout(for: screen, placement: placement)
    }

    func testEdges() {
        XCTAssertEqual(Placement.top.edge, .top)
        XCTAssertEqual(Placement.topLeft.edge, .top)
        XCTAssertEqual(Placement.topRight.edge, .top)
        XCTAssertEqual(Placement.bottom.edge, .bottom)
        XCTAssertEqual(Placement.left.edge, .left)
        XCTAssertEqual(Placement.right.edge, .right)
        XCTAssertTrue(ScreenEdge.left.isSide)
        XCTAssertFalse(ScreenEdge.bottom.isSide)
    }

    func testTopCentreIsUnchanged() {
        XCTAssertEqual(layout(notched, .top), NotchGeometry.layout(for: notched))
    }

    func testEveryOtherPlacementFloatsAnIslandEvenOnANotchedMac() {
        for placement in Placement.allCases where placement != .top {
            let result = layout(notched, placement)
            XCTAssertEqual(result.style, .island, "\(placement)")
            XCTAssertNotEqual(result.closedRect.minY, notched.frame.maxY - notched.safeAreaTop, "\(placement)")
        }
    }

    func testTopCornersSitBelowTheMenuBar() {
        let left = layout(docked, .topLeft)
        XCTAssertEqual(left.closedRect.maxY, docked.visibleFrame.maxY - sizes.edgeMargin)
        XCTAssertEqual(left.closedRect.minX, docked.visibleFrame.minX + sizes.cornerInset)
        XCTAssertEqual(left.closedRect.size, sizes.island)

        let right = layout(docked, .topRight)
        XCTAssertEqual(right.closedRect.maxY, docked.visibleFrame.maxY - sizes.edgeMargin)
        XCTAssertEqual(right.closedRect.maxX, docked.visibleFrame.maxX - sizes.cornerInset)
    }

    func testTopCornerSurfacesGrowAwayFromTheCorner() {
        let left = layout(docked, .topLeft)
        let surface = left.surfaceRect(size: CGSize(width: 500, height: 200))
        XCTAssertEqual(surface.minX, left.closedRect.minX)
        XCTAssertEqual(surface.maxY, left.closedRect.maxY)

        let right = layout(docked, .topRight)
        let mirrored = right.surfaceRect(size: CGSize(width: 500, height: 200))
        XCTAssertEqual(mirrored.maxX, right.closedRect.maxX)
        XCTAssertEqual(mirrored.maxY, right.closedRect.maxY)
    }

    func testCornerHitRegionLeavesTheMenuBarAlone() {
        let left = layout(docked, .topLeft)
        let region = left.hitRegion(for: left.closedRect)
        XCTAssertEqual(region.maxY, docked.visibleFrame.maxY)
        XCTAssertFalse(region.contains(CGPoint(x: left.closedRect.midX, y: docked.frame.maxY - 2)))
    }

    func testBottomSitsAboveTheDockAndGrowsUp() {
        let bottom = layout(docked, .bottom)
        XCTAssertEqual(bottom.closedRect.minY, docked.visibleFrame.minY + sizes.edgeMargin)
        XCTAssertEqual(bottom.closedRect.midX, docked.frame.midX)

        let surface = bottom.surfaceRect(size: CGSize(width: 500, height: 200))
        XCTAssertEqual(surface.minY, bottom.closedRect.minY)
        XCTAssertEqual(surface.midX, bottom.closedRect.midX)
        XCTAssertEqual(bottom.peekRect.minY, bottom.closedRect.minY)
        XCTAssertGreaterThan(bottom.peekRect.height, bottom.closedRect.height)
    }

    func testBottomHitRegionStopsAtTheDock() {
        let bottom = layout(docked, .bottom)
        let region = bottom.hitRegion(for: bottom.closedRect)
        XCTAssertEqual(region.minY, docked.visibleFrame.minY)
        XCTAssertFalse(region.contains(CGPoint(x: bottom.closedRect.midX, y: 40)))
    }

    func testBottomWithoutTheDockReachesTheScreenEdge() {
        let bottom = layout(bare, .bottom)
        let region = bottom.hitRegion(for: bottom.closedRect)
        XCTAssertTrue(region.contains(CGPoint(x: bottom.closedRect.midX, y: 0.5)))
    }

    func testSideEdgesRestAsAnUprightTabFlushWithTheEdge() {
        let left = layout(docked, .left)
        XCTAssertEqual(left.closedRect.minX, docked.visibleFrame.minX)
        XCTAssertEqual(left.closedRect.midY, docked.visibleFrame.midY)
        XCTAssertGreaterThan(left.closedRect.height, left.closedRect.width)
        XCTAssertEqual(left.barHeight, sizes.island.height)

        let right = layout(docked, .right)
        XCTAssertEqual(right.closedRect.maxX, docked.visibleFrame.maxX)
    }

    func testSideSurfacesSlideOutSideways() {
        let left = layout(docked, .left)
        let surface = left.surfaceRect(size: CGSize(width: 500, height: 200))
        XCTAssertEqual(surface.minX, left.closedRect.minX)
        XCTAssertEqual(surface.midY, left.closedRect.midY)
        XCTAssertEqual(left.peekRect.minX, left.closedRect.minX)
        XCTAssertGreaterThan(left.peekRect.width, left.closedRect.width)

        let right = layout(docked, .right)
        XCTAssertEqual(right.surfaceRect(size: CGSize(width: 500, height: 200)).maxX, right.closedRect.maxX)
    }

    func testSideHitRegionReachesTheEdge() {
        let left = layout(bare, .left)
        XCTAssertTrue(left.hitRegion(for: left.closedRect).contains(CGPoint(x: 0.5, y: left.closedRect.midY)))
        let right = layout(bare, .right)
        XCTAssertTrue(
            right.hitRegion(for: right.closedRect).contains(CGPoint(x: bare.frame.maxX - 0.5, y: right.closedRect.midY))
        )
    }

    func testSideDockPushesTheTabInward() {
        let dockOnLeft = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 80, y: 0, width: 1840, height: 1056)
        )
        let left = layout(dockOnLeft, .left)
        XCTAssertEqual(left.closedRect.minX, 80)
        XCTAssertEqual(left.hitRegion(for: left.closedRect).minX, 80)
    }

    func testTallSurfacesStayOnScreen() {
        let left = layout(docked, .left)
        let surface = left.surfaceRect(size: CGSize(width: 400, height: 2000))
        XCTAssertGreaterThanOrEqual(surface.minY, docked.frame.minY)
        XCTAssertLessThanOrEqual(surface.maxY, docked.frame.maxY)
    }

    func testPanelHoldsTheLargestSurfaceInEveryPlacement() {
        for screen in [docked, bare, notched] {
            for placement in Placement.allCases {
                let result = layout(screen, placement)
                let largest = result.surfaceRect(size: sizes.maxSurface)
                XCTAssertTrue(result.panelFrame.contains(largest), "\(placement)")
                XCTAssertTrue(result.panelFrame.contains(result.closedRect), "\(placement)")
                XCTAssertTrue(screen.frame.contains(result.panelFrame), "\(placement)")
            }
        }
    }

    // MARK: Sizing

    func testSideCompactPillStandsUpright() {
        let left = layout(docked, .left)
        let pill = SurfaceSizing.rect(for: .compact(wide: false), in: left)
        XCTAssertEqual(pill.size, ActivityMetrics.sidePillSize)
        XCTAssertGreaterThan(pill.height, pill.width)
        XCTAssertEqual(pill.minX, left.closedRect.minX)
        XCTAssertEqual(pill.midY, left.closedRect.midY)

        let wide = SurfaceSizing.rect(for: .compact(wide: true), in: left)
        XCTAssertGreaterThanOrEqual(wide.width, pill.width)
        XCTAssertGreaterThanOrEqual(wide.height, pill.height)
    }

    func testBubblesSitBesideTopAndBottomPills() {
        let pill = CGRect(x: 500, y: 100, width: 200, height: 32)
        for placement in [Placement.top, .bottom] {
            let rects = SurfaceSizing.bubbleRects(beside: pill, count: 2, placement: placement)
            XCTAssertEqual(rects[0].minX, pill.maxX + SurfaceSizing.bubbleGap)
            XCTAssertEqual(rects[1].maxX, pill.minX - SurfaceSizing.bubbleGap)
        }
    }

    func testCornerBubblesBothGoInward() {
        let pill = CGRect(x: 20, y: 1000, width: 200, height: 32)
        let left = SurfaceSizing.bubbleRects(beside: pill, count: 2, placement: .topLeft)
        XCTAssertTrue(left.allSatisfy { $0.minX > pill.maxX })
        XCTAssertLessThan(left[0].minX, left[1].minX)

        let right = SurfaceSizing.bubbleRects(beside: pill, count: 2, placement: .topRight)
        XCTAssertTrue(right.allSatisfy { $0.maxX < pill.minX })
        XCTAssertGreaterThan(right[0].minX, right[1].minX)
    }

    func testSideBubblesStackAlongTheEdge() {
        let pill = CGRect(x: 0, y: 500, width: 50, height: 92)
        let left = SurfaceSizing.bubbleRects(beside: pill, count: 2, placement: .left)
        XCTAssertEqual(left[0].maxY, pill.minY - SurfaceSizing.bubbleGap)
        XCTAssertEqual(left[1].minY, pill.maxY + SurfaceSizing.bubbleGap)
        XCTAssertTrue(left.allSatisfy { $0.minX == pill.minX && $0.width == pill.width && $0.height == pill.width })

        let right = SurfaceSizing.bubbleRects(beside: pill, count: 1, placement: .right)
        XCTAssertEqual(right[0].maxX, pill.maxX)
    }

    func testNavPillSitsAwayFromTheEdge() {
        let surface = CGRect(x: 500, y: 100, width: 400, height: 200)
        XCTAssertLessThan(SurfaceSizing.navPillRect(for: surface, placement: .top).maxY, surface.minY)
        XCTAssertLessThan(SurfaceSizing.navPillRect(for: surface, placement: .left).maxY, surface.minY)
        XCTAssertGreaterThan(SurfaceSizing.navPillRect(for: surface, placement: .bottom).minY, surface.maxY)
    }

    func testMuteZoneIsTheMicNotTheWholeSidePill() {
        let wide = CGRect(x: 500, y: 1000, width: 300, height: 32)
        let zone = SurfaceSizing.meetingMuteZone(in: wide, placement: .top)
        XCTAssertEqual(zone.minX, wide.maxX - SurfaceSizing.meetingMuteWidth)
        XCTAssertEqual(zone.height, wide.height)

        // The upright pill is narrower than the old right-hand zone; only its glyph row mutes.
        let upright = CGRect(x: 0, y: 400, width: 58, height: 96)
        let side = SurfaceSizing.meetingMuteZone(in: upright, placement: .left)
        XCTAssertEqual(side.minY, upright.midY)
        XCTAssertEqual(side.maxY, upright.maxY)
        XCTAssertFalse(side.contains(CGPoint(x: upright.midX, y: upright.minY + 10)))
    }

    func testOpeningSwipePointsAwayFromTheEdge() {
        XCTAssertEqual(Placement.top.openingSwipe, .down)
        XCTAssertEqual(Placement.topLeft.openingSwipe, .down)
        XCTAssertEqual(Placement.bottom.openingSwipe, .up)
        XCTAssertEqual(Placement.left.openingSwipe, .right)
        XCTAssertEqual(Placement.right.openingSwipe, .left)
    }
}
