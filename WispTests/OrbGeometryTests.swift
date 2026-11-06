import CoreGraphics
import XCTest

@testable import WispCore

final class OrbGeometryTests: XCTestCase {
    /// A 14" MacBook Pro: menu bar 38 pt, Dock at the bottom.
    private let screen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 874))
    private var visible: CGRect { screen.visibleFrame }
    private let size: CGFloat = 40

    func testANewOrbStartsTopRightBelowTheMenuBar() {
        let layout = NotchGeometry.layout(for: screen, placement: .floating)
        XCTAssertEqual(layout.style, .island)
        XCTAssertEqual(layout.closedRect.size, CGSize(width: size, height: size))
        XCTAssertGreaterThan(layout.closedRect.midX, visible.midX)
        XCTAssertLessThanOrEqual(layout.closedRect.maxY, visible.maxY)
        XCTAssertEqual(layout.anchor, .topRight)
    }

    func testTheOrbStaysInsideTheVisibleFrame() {
        for point in [
            CGPoint(x: -100, y: -100), CGPoint(x: 5000, y: 5000), CGPoint(x: 0, y: 980), CGPoint(x: 1512, y: 0),
        ] {
            let layout = NotchGeometry.layout(for: screen, placement: .floating, orbCentre: point)
            XCTAssertTrue(visible.contains(layout.closedRect), "\(point) gave \(layout.closedRect)")
        }
    }

    func testItOpensTowardTheMiddleOfTheScreen() {
        XCTAssertEqual(OrbGeometry.anchor(for: CGPoint(x: 100, y: 800), in: visible), .topLeft)
        XCTAssertEqual(OrbGeometry.anchor(for: CGPoint(x: 756, y: 800), in: visible), .top)
        XCTAssertEqual(OrbGeometry.anchor(for: CGPoint(x: 1400, y: 800), in: visible), .topRight)
        XCTAssertEqual(OrbGeometry.anchor(for: CGPoint(x: 1400, y: 200), in: visible), .bottom)
    }

    func testSurfacesFitTheVisibleFrame() {
        for point in [CGPoint(x: 30, y: 900), CGPoint(x: 1480, y: 100), CGPoint(x: 756, y: 500)] {
            let layout = NotchGeometry.layout(for: screen, placement: .floating, orbCentre: point)
            let surface = layout.surfaceRect(size: CGSize(width: 640, height: 400))
            XCTAssertTrue(visible.contains(surface), "\(point) gave \(surface)")
            XCTAssertTrue(screen.frame.contains(layout.panelFrame))
        }
    }

    func testAnOpeningSurfaceGrowsOutOfTheOrb() {
        let layout = NotchGeometry.layout(for: screen, placement: .floating, orbCentre: CGPoint(x: 200, y: 800))
        let surface = layout.surfaceRect(size: CGSize(width: 300, height: 200))
        XCTAssertEqual(surface.minX, layout.closedRect.minX)
        XCTAssertEqual(surface.maxY, layout.closedRect.maxY)
    }

    func testTheHitRegionIsTheOrbNotAnEdgeBand() {
        let layout = NotchGeometry.layout(for: screen, placement: .floating, orbCentre: CGPoint(x: 756, y: 500))
        let region = layout.hitRegion(for: layout.closedRect)
        XCTAssertLessThan(region.maxY, visible.maxY)
        XCTAssertEqual(region.height, size + 12, accuracy: 0.5)
        XCTAssertFalse(region.contains(CGPoint(x: 756, y: 900)))
    }

    func testReleasingNearAnEdgeSnapsToIt() {
        let half = size / 2 + OrbGeometry.margin
        let near = OrbGeometry.snapped(CGPoint(x: half + 10, y: 500), in: visible, size: size)
        XCTAssertEqual(near.x, visible.minX + half)
        let corner = OrbGeometry.snapped(CGPoint(x: 1490, y: 930), in: visible, size: size)
        XCTAssertEqual(corner, CGPoint(x: visible.maxX - half, y: visible.maxY - half))
        let middle = CGPoint(x: 700, y: 500)
        XCTAssertEqual(OrbGeometry.snapped(middle, in: visible, size: size), middle)
    }

    func testTheNotchNeedsAPullButTheOrbMovesAtANudge() {
        let start = CGPoint(x: 756, y: 960)
        XCTAssertFalse(OrbGeometry.startsDrag(from: start, to: CGPoint(x: 756, y: 930), floating: false))
        XCTAssertTrue(OrbGeometry.startsDrag(from: start, to: CGPoint(x: 756, y: 915), floating: false))
        XCTAssertTrue(OrbGeometry.startsDrag(from: start, to: CGPoint(x: 761, y: 960), floating: true))
        XCTAssertFalse(OrbGeometry.startsDrag(from: start, to: CGPoint(x: 758, y: 960), floating: true))
    }

    func testDroppingAtTheTopCentreDocks() {
        XCTAssertTrue(OrbGeometry.docks(CGPoint(x: 756, y: 920), in: visible, systemIsland: false))
        XCTAssertFalse(OrbGeometry.docks(CGPoint(x: 756, y: 600), in: visible, systemIsland: false))
        XCTAssertFalse(OrbGeometry.docks(CGPoint(x: 200, y: 920), in: visible, systemIsland: false))
        XCTAssertFalse(OrbGeometry.docks(CGPoint(x: 756, y: 920), in: visible, systemIsland: true))
    }

    func testAnOrbKeepsClearOfASystemIsland() {
        let layout = NotchGeometry.layout(
            for: screen, placement: .floating, orbCentre: CGPoint(x: 756, y: 920), avoidsTopCentre: true)
        let zone = OrbGeometry.islandZone(in: visible)
        XCTAssertFalse(zone.intersects(layout.closedRect))
    }

    func testPositionsRoundTripAsText() {
        XCTAssertEqual(OrbGeometry.encode(CGPoint(x: 120.4, y: 88.6)), "120,89")
        XCTAssertEqual(OrbGeometry.decode("120,89"), CGPoint(x: 120, y: 89))
        XCTAssertEqual(OrbGeometry.decode(" -5 , 7 "), CGPoint(x: -5, y: 7))
        XCTAssertNil(OrbGeometry.decode("nope"))
        XCTAssertNil(OrbGeometry.decode("1,2,3"))
    }
}
