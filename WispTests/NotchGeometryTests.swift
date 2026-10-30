import CoreGraphics
import XCTest

@testable import WispCore

final class NotchGeometryTests: XCTestCase {
    // A 14" MacBook Pro at default scaling: 1512x982 points, 38 pt camera housing
    // from x=692 to x=820.
    private let notched = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        safeAreaTop: 38,
        auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 692, height: 38),
        auxiliaryTopRight: CGRect(x: 820, y: 944, width: 692, height: 38)
    )

    // A 1080p external display to the right of it.
    private let external = ScreenMetrics(
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1056)
    )

    func testNotchedScreenUsesCameraHousing() {
        let layout = NotchGeometry.layout(for: notched)
        XCTAssertEqual(layout.style, .notch)
        XCTAssertEqual(layout.closedRect, CGRect(x: 692, y: 944, width: 128, height: 38))
    }

    func testNotchlessScreenDrawsANotchFlushWithTheTop() {
        let layout = NotchGeometry.layout(for: external)
        XCTAssertEqual(layout.style, .notch)
        XCTAssertEqual(layout.closedRect.midX, external.frame.midX)
        XCTAssertEqual(layout.closedRect.maxY, external.frame.maxY)
        XCTAssertEqual(layout.closedRect.width, NotchSizes.standard.drawnNotchWidth)
        XCTAssertEqual(layout.closedRect.height, external.menuBarHeight)
    }

    func testIslandFloatsBelowTheTop() {
        let sizes = NotchSizes.standard
        let layout = NotchGeometry.layout(for: external, prefersIsland: true)
        XCTAssertEqual(layout.style, .island)
        XCTAssertEqual(layout.closedRect.maxY, external.frame.maxY - sizes.islandTopMargin)
        XCTAssertEqual(layout.closedRect.size, sizes.island)
    }

    func testNotchedScreenIgnoresIslandPreference() {
        XCTAssertEqual(NotchGeometry.layout(for: notched, prefersIsland: true).style, .notch)
    }

    func testSurfacesHangFromTheTopCentredOnTheNotch() {
        let layout = NotchGeometry.layout(for: notched)
        let surface = layout.surfaceRect(size: CGSize(width: 451, height: 160))
        XCTAssertEqual(surface.maxY, notched.frame.maxY)
        XCTAssertEqual(surface.midX, layout.closedRect.midX)
        XCTAssertEqual(layout.peekRect.maxY, notched.frame.maxY)
        XCTAssertGreaterThan(layout.peekRect.width, layout.closedRect.width)
        // Hover swells the notch downward too, not just sideways.
        XCTAssertGreaterThanOrEqual(layout.peekRect.height - layout.closedRect.height, 8)
    }

    func testCompactRectAddsWingsBothSides() {
        let layout = NotchGeometry.layout(for: notched)
        let compact = layout.compactRect(wing: 70, height: 20)
        XCTAssertEqual(compact.width, layout.closedRect.width + 140)
        XCTAssertEqual(compact.height, layout.closedRect.height)
        XCTAssertEqual(compact.midX, layout.closedRect.midX)
    }

    func testSurfaceIsClampedToTheScreen() {
        let edge = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 600, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 776)
        )
        let layout = NotchGeometry.layout(for: edge)
        let surface = layout.surfaceRect(size: CGSize(width: 900, height: 200))
        XCTAssertEqual(surface.width, 600)
        XCTAssertEqual(surface.minX, 0)
    }

    func testPanelContainsLargestSurfaceAndStaysOnScreen() {
        for screen in [notched, external] {
            let layout = NotchGeometry.layout(for: screen)
            let largest = layout.surfaceRect(size: NotchSizes.standard.maxSurface)
            XCTAssertTrue(layout.panelFrame.contains(largest))
            XCTAssertEqual(layout.panelFrame.maxY, screen.frame.maxY)
            XCTAssertGreaterThanOrEqual(layout.panelFrame.minX, screen.frame.minX)
            XCTAssertLessThanOrEqual(layout.panelFrame.maxX, screen.frame.maxX)
        }
    }

    func testHiddenMenuBarHasZeroHeight() {
        let fullScreen = ScreenMetrics(frame: external.frame, visibleFrame: external.frame)
        XCTAssertEqual(fullScreen.menuBarHeight, 0)
        XCTAssertEqual(external.menuBarHeight, 24)
        let layout = NotchGeometry.layout(for: fullScreen)
        XCTAssertEqual(layout.closedRect.height, NotchSizes.standard.drawnNotchFallbackHeight)
    }

    func testHitRegionReachesTheTopEdge() {
        let layout = NotchGeometry.layout(for: notched)
        let region = layout.hitRegion(for: layout.closedRect)
        XCTAssertTrue(region.contains(CGPoint(x: layout.closedRect.midX, y: notched.frame.maxY - 0.5)))
        XCTAssertFalse(region.contains(CGPoint(x: 100, y: 960)))
    }

    func testClosedRadiiFollowHeightWithinBounds() {
        XCTAssertEqual(ShellMetrics.closedTopRadius(height: 20), 8)
        XCTAssertEqual(ShellMetrics.closedTopRadius(height: 38), 38 * 0.24, accuracy: 1e-9)
        XCTAssertEqual(ShellMetrics.closedTopRadius(height: 60), 10)
        XCTAssertEqual(ShellMetrics.closedBottomRadius(height: 20), 11)
        XCTAssertEqual(ShellMetrics.closedBottomRadius(height: 60), 13)
    }
}
