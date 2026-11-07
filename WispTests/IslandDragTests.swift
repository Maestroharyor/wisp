import CoreGraphics
import XCTest

@testable import WispCore

final class IslandSpotTests: XCTestCase {
    func testASpotRoundTripsAsText() {
        let spot = IslandSpot(placement: .topRight, centre: CGPoint(x: 900.4, y: 600.6))
        XCTAssertEqual(spot.encoded, "topRight@900,601")
        XCTAssertEqual(
            IslandSpot(encoded: "topRight@900,601"), IslandSpot(placement: .topRight, centre: CGPoint(x: 900, y: 601)))
        XCTAssertEqual(IslandSpot(encoded: "bottom@-20,7")?.centre, CGPoint(x: -20, y: 7))
    }

    func testBrokenTextIsIgnored() {
        for text in ["", "topRight", "nope@1,2", "topRight@1", "topRight@a,b", "@1,2"] {
            XCTAssertNil(IslandSpot(encoded: text), text)
        }
    }

    func testASpotOnlyAppliesToThePlacementItWasMovedFrom() {
        let spot = IslandSpot(placement: .topRight, centre: CGPoint(x: 400, y: 500))
        XCTAssertEqual(spot.centre(for: .topRight), CGPoint(x: 400, y: 500))
        XCTAssertNil(spot.centre(for: .bottom))
        XCTAssertNil(spot.centre(for: .floating))
    }
}

final class IslandLayoutTests: XCTestCase {
    /// A 14" MacBook Pro: menu bar 38 pt, Dock at the bottom.
    private let screen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 874))
    private var visible: CGRect { screen.visibleFrame }
    private let island = NotchSizes.standard.island

    /// The same screen with a camera housing, so Top is a real notch.
    private let notched = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 874),
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 660, height: 32),
        auxiliaryTopRight: CGRect(x: 852, y: 950, width: 660, height: 32))

    func testIslandsMoveButNotchesSideTabsAndTheOrbDoNot() {
        for placement in [Placement.topLeft, .topRight, .bottom] {
            XCTAssertTrue(NotchGeometry.layout(for: screen, placement: placement).movesAsIsland, "\(placement)")
        }
        XCTAssertTrue(NotchGeometry.layout(for: screen, prefersIsland: true, placement: .top).movesAsIsland)
        XCTAssertFalse(NotchGeometry.layout(for: screen, placement: .top).movesAsIsland)
        XCTAssertFalse(NotchGeometry.layout(for: notched, prefersIsland: true, placement: .top).movesAsIsland)
        for placement in [Placement.left, .right, .floating] {
            XCTAssertFalse(NotchGeometry.layout(for: screen, placement: placement).movesAsIsland, "\(placement)")
        }
    }

    func testAMovedIslandSitsWhereItWasDroppedAndKeepsItsSize() {
        let centre = CGPoint(x: 700, y: 500)
        let layout = NotchGeometry.layout(for: screen, placement: .topRight, islandCentre: centre)
        XCTAssertTrue(layout.moved)
        XCTAssertEqual(layout.placement, .topRight)
        XCTAssertEqual(layout.style, .island)
        XCTAssertEqual(layout.closedRect.size, island)
        XCTAssertEqual(layout.closedRect.midX, centre.x)
        XCTAssertEqual(layout.closedRect.midY, centre.y)
    }

    func testWithoutASpotTheIslandStaysInItsCorner() {
        let layout = NotchGeometry.layout(for: screen, placement: .topRight)
        XCTAssertFalse(layout.moved)
        XCTAssertGreaterThan(layout.closedRect.midX, visible.maxX - 100)
    }

    func testShellsThatDoNotMoveIgnoreASpot() {
        let centre = CGPoint(x: 700, y: 500)
        let notch = NotchGeometry.layout(for: notched, placement: .top, islandCentre: centre)
        XCTAssertFalse(notch.moved)
        XCTAssertEqual(notch.style, .notch)
        let side = NotchGeometry.layout(for: screen, placement: .left, islandCentre: centre)
        XCTAssertFalse(side.moved)
        let orb = NotchGeometry.layout(for: screen, placement: .floating, islandCentre: centre)
        XCTAssertFalse(orb.moved)
        XCTAssertEqual(orb.closedRect.width, NotchSizes.standard.orb)
    }

    func testATopIslandCanMoveToo() {
        let layout = NotchGeometry.layout(
            for: screen, prefersIsland: true, placement: .top, islandCentre: CGPoint(x: 300, y: 300))
        XCTAssertTrue(layout.moved)
        XCTAssertEqual(layout.anchor, .bottom)
    }

    func testAMovedIslandOpensTowardTheMiddleOfTheScreen() {
        let low = NotchGeometry.layout(for: screen, placement: .topRight, islandCentre: CGPoint(x: 200, y: 200))
        XCTAssertEqual(low.anchor, .bottom)
        let grown = low.surfaceRect(size: CGSize(width: 400, height: 300))
        XCTAssertEqual(grown.minY, low.closedRect.minY)

        let upperLeft = NotchGeometry.layout(for: screen, placement: .bottom, islandCentre: CGPoint(x: 200, y: 800))
        XCTAssertEqual(upperLeft.anchor, .topLeft)
        let shelf = upperLeft.surfaceRect(size: CGSize(width: 400, height: 300))
        XCTAssertEqual(shelf.minX, upperLeft.closedRect.minX)
        XCTAssertEqual(shelf.maxY, upperLeft.closedRect.maxY)
    }

    func testAMovedIslandStaysOnScreenAndItsSurfacesFitTheVisibleFrame() {
        for point in [CGPoint(x: -400, y: -400), CGPoint(x: 5000, y: 5000), CGPoint(x: 756, y: 500)] {
            let layout = NotchGeometry.layout(for: screen, placement: .topLeft, islandCentre: point)
            XCTAssertTrue(visible.contains(layout.closedRect), "\(point) gave \(layout.closedRect)")
            XCTAssertTrue(visible.contains(layout.surfaceRect(size: CGSize(width: 640, height: 400))))
            XCTAssertTrue(screen.frame.contains(layout.panelFrame))
        }
    }

    func testAMovedIslandsPanelIsNotStretchedToAnEdge() {
        let layout = NotchGeometry.layout(for: screen, placement: .topRight, islandCentre: CGPoint(x: 756, y: 200))
        XCTAssertLessThan(layout.panelFrame.maxY, screen.frame.maxY)
        XCTAssertTrue(layout.panelFrame.contains(layout.closedRect))
    }

    func testTheHitRegionIsTheIslandNotAnEdgeBand() {
        let layout = NotchGeometry.layout(for: screen, placement: .topRight, islandCentre: CGPoint(x: 756, y: 500))
        let region = layout.hitRegion(for: layout.closedRect)
        XCTAssertEqual(region.height, island.height + 12, accuracy: 0.5)
        XCTAssertFalse(region.contains(CGPoint(x: 756, y: 900)))
    }

    func testAMovedIslandKeepsClearOfASystemIsland() {
        let layout = NotchGeometry.layout(
            for: screen, placement: .topRight, islandCentre: CGPoint(x: 756, y: 930), avoidsTopCentre: true)
        XCTAssertFalse(OrbGeometry.islandZone(in: visible).intersects(layout.closedRect))
    }
}

final class IslandDragRuleTests: XCTestCase {
    private let screen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 874))

    func testADragStartsOnTheIslandWhileWispTakesTheClick() {
        let layout = NotchGeometry.layout(for: screen, placement: .topRight)
        let shape = layout.closedRect
        let press = CGPoint(x: shape.midX, y: shape.midY)
        XCTAssertTrue(IslandDrag.ownsPointer(at: press, layout: layout, shape: shape))
        XCTAssertTrue(IslandDrag.mayStart(at: press, layout: layout, shape: shape, panelTakesClicks: true))
    }

    func testNoDragWhenTheClickAlsoReachesTheAppUnderneath() {
        let layout = NotchGeometry.layout(for: screen, placement: .topRight)
        let shape = layout.closedRect
        let press = CGPoint(x: shape.midX, y: shape.midY)
        XCTAssertFalse(IslandDrag.mayStart(at: press, layout: layout, shape: shape, panelTakesClicks: false))
    }

    func testNoDragFromTheHoverMarginAroundTheIsland() {
        let layout = NotchGeometry.layout(for: screen, placement: .bottom)
        let shape = layout.closedRect
        // Inside the hit region's tolerance, but over the window beneath.
        let press = CGPoint(x: shape.maxX + 3, y: shape.midY)
        XCTAssertTrue(layout.hitRegion(for: shape).contains(press))
        XCTAssertFalse(IslandDrag.ownsPointer(at: press, layout: layout, shape: shape))
        XCTAssertFalse(IslandDrag.mayStart(at: press, layout: layout, shape: shape, panelTakesClicks: true))
    }

    func testAWiderActivityPillCountsAsTheIsland() {
        let layout = NotchGeometry.layout(for: screen, placement: .topRight)
        let pill = layout.compactRect(wing: 60, height: layout.closedRect.height)
        let press = CGPoint(x: pill.minX + 4, y: pill.midY)
        XCTAssertFalse(layout.closedRect.contains(press))
        XCTAssertTrue(IslandDrag.mayStart(at: press, layout: layout, shape: pill, panelTakesClicks: true))
    }

    func testNotchesSideTabsAndTheOrbKeepTheirOwnRules() {
        for placement in [Placement.top, .left, .right, .floating] {
            let layout = NotchGeometry.layout(for: screen, placement: placement)
            let shape = layout.closedRect
            let press = CGPoint(x: shape.midX, y: shape.midY)
            XCTAssertFalse(
                IslandDrag.mayStart(at: press, layout: layout, shape: shape, panelTakesClicks: true), "\(placement)")
        }
    }
}

final class IslandDropTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 70, width: 1512, height: 874)
    private let size = NotchSizes.standard.island
    private let home = CGPoint(x: 1435, y: 922)

    func testDroppedInTheOpenItStaysThere() {
        let drop = IslandDrop.outcome(
            dropped: CGPoint(x: 700, y: 500), in: visible, size: size, systemIsland: false, home: home)
        XCTAssertEqual(drop, .move(CGPoint(x: 700, y: 500)))
    }

    func testDroppedNearAnEdgeItSettlesFlushAgainstIt() {
        let halfWidth = size.width / 2 + OrbGeometry.margin
        let drop = IslandDrop.outcome(
            dropped: CGPoint(x: halfWidth + 10, y: 500), in: visible, size: size, systemIsland: false, home: home)
        XCTAssertEqual(drop, .move(CGPoint(x: visible.minX + halfWidth, y: 500)))
        let halfHeight = size.height / 2 + OrbGeometry.margin
        let low = IslandDrop.outcome(
            dropped: CGPoint(x: 700, y: visible.minY + halfHeight + 5), in: visible, size: size, systemIsland: false,
            home: home)
        XCTAssertEqual(low, .move(CGPoint(x: 700, y: visible.minY + halfHeight)))
    }

    func testDroppedOffScreenItComesBackInside() {
        guard
            case .move(let point) = IslandDrop.outcome(
                dropped: CGPoint(x: -900, y: -900), in: visible, size: size, systemIsland: false, home: home)
        else { return XCTFail("expected a move") }
        let rect = CGRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        XCTAssertTrue(visible.contains(rect))
    }

    func testDroppedBackOnItsOwnSpotItGoesHome() {
        let drop = IslandDrop.outcome(
            dropped: CGPoint(x: home.x - 6, y: home.y - 4), in: visible, size: size, systemIsland: false, home: home)
        XCTAssertEqual(drop, .restore)
    }

    func testATopIslandDroppedJustBelowItsSpotOverTheMenuBarGoesHome() {
        let topHome = CGPoint(x: 756, y: 962)
        let drop = IslandDrop.outcome(
            dropped: CGPoint(x: 760, y: 925), in: visible, size: size, systemIsland: false, home: topHome)
        XCTAssertEqual(drop, .restore)
    }

    func testItNeverRestsUnderASystemIsland() {
        guard
            case .move(let point) = IslandDrop.outcome(
                dropped: CGPoint(x: 756, y: 930), in: visible, size: size, systemIsland: true, home: home)
        else { return XCTFail("expected a move") }
        let rect = CGRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        XCTAssertFalse(OrbGeometry.islandZone(in: visible).intersects(rect))
    }

    func testSizedFitAndSnapMatchTheOrbsForASquare() {
        let point = CGPoint(x: 30, y: 930)
        XCTAssertEqual(
            OrbGeometry.fitted(point, in: visible, size: CGSize(width: 44, height: 44)),
            OrbGeometry.fitted(point, in: visible, size: 44))
        XCTAssertEqual(
            OrbGeometry.snapped(point, in: visible, size: CGSize(width: 44, height: 44)),
            OrbGeometry.snapped(point, in: visible, size: 44))
    }
}
