import CoreGraphics
import XCTest

@testable import WispCore

final class ShelfHeightTests: XCTestCase {
    // A 14" MacBook Pro: the menu bar takes the top 32 pt, so 950 pt are visible under it.
    private let laptop = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    )
    // A 1440p display beside it, with the Dock taking 70 pt at the bottom.
    private let tall = ScreenMetrics(
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 70, width: 2560, height: 1345)
    )
    // A short display, where the nav pill under the shelf decides the limit.
    private let short = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 800, height: 300),
        visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 276)
    )

    private let solo = SurfaceSpec.widgetSolo(wide: true)

    func testNoExtraKeepsTheUsualShelf() {
        let layout = NotchGeometry.layout(for: laptop)
        XCTAssertEqual(
            SurfaceSizing.rect(for: solo, in: layout, extraHeight: 0), SurfaceSizing.rect(for: solo, in: layout))
        XCTAssertEqual(
            SurfaceSizing.rect(for: solo, in: layout, extraHeight: -40), SurfaceSizing.rect(for: solo, in: layout))
    }

    func testExtraGrowsTheShelfDownFromTheTop() {
        let layout = NotchGeometry.layout(for: laptop)
        let base = SurfaceSizing.rect(for: solo, in: layout)
        let taller = SurfaceSizing.rect(for: solo, in: layout, extraHeight: 120)
        XCTAssertEqual(taller.height, base.height + 120)
        XCTAssertEqual(taller.maxY, base.maxY)
        XCTAssertEqual(taller.width, base.width)
        XCTAssertEqual(taller.midX, base.midX)
    }

    func testExtraIsCappedAtSixtyPercentOfTheVisibleScreen() {
        let layout = NotchGeometry.layout(for: laptop)
        let tallest = SurfaceSizing.rect(for: solo, in: layout, extraHeight: 5000)
        // The bottom stops 60% of the way down the 950 pt under the menu bar.
        XCTAssertEqual(tallest.minY, 950 - 950 * ShelfHeight.maxScreenFraction, accuracy: 0.001)
        XCTAssertEqual(tallest.height, ShelfHeight.maxHeight(in: layout), accuracy: 0.001)
        XCTAssertGreaterThan(tallest.height, NotchSizes.standard.maxSurface.height)
    }

    func testTallerScreensGetMoreRoomUpToTheCap() {
        let hd = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056))
        let hdTallest = SurfaceSizing.rect(for: solo, in: NotchGeometry.layout(for: hd), extraHeight: 5000)
        XCTAssertEqual(hdTallest.minY, 1056 - 1056 * ShelfHeight.maxScreenFraction, accuracy: 0.001)
        let laptopTallest = SurfaceSizing.rect(for: solo, in: NotchGeometry.layout(for: laptop), extraHeight: 5000)
        XCTAssertGreaterThan(hdTallest.height, laptopTallest.height)
        // 60% of the 1440p display would be 832 pt; the shelf stops at the cap.
        let capped = SurfaceSizing.rect(for: solo, in: NotchGeometry.layout(for: tall), extraHeight: 5000)
        XCTAssertEqual(capped.height, ShelfHeight.heightCap)
    }

    func testShortScreensKeepRoomForTheNavPill() {
        let layout = NotchGeometry.layout(for: short)
        let tallest = SurfaceSizing.rect(for: solo, in: layout, extraHeight: 5000)
        let pill = SurfaceSizing.navPillRect(for: tallest, placement: layout.anchor)
        XCTAssertGreaterThanOrEqual(pill.minY, short.visibleFrame.minY)
        // Never shorter than the usual shelf, even when the screen has no room to spare.
        XCTAssertGreaterThanOrEqual(tallest.height, SurfaceSizing.rect(for: solo, in: layout).height)
    }

    func testExtraAppliesOnTopOfTheShelfSize() {
        let layout = NotchGeometry.layout(for: laptop)
        let zoomed = SurfaceSizing.rect(for: solo, in: layout, contentScale: 0.8)
        let taller = SurfaceSizing.rect(for: solo, in: layout, contentScale: 0.8, extraHeight: 50)
        XCTAssertEqual(taller.height, zoomed.height + 50)
        XCTAssertEqual(SurfaceSizing.shelfExtra(for: solo, in: layout, contentScale: 0.8, requested: 50), 50)
    }

    func testOnlyShelfPagesGrow() {
        let layout = NotchGeometry.layout(for: laptop)
        for spec: SurfaceSpec in [.closed, .peek, .compact(wide: true), .medium, .notification(extra: 0)] {
            XCTAssertEqual(
                SurfaceSizing.rect(for: spec, in: layout, extraHeight: 100), SurfaceSizing.rect(for: spec, in: layout),
                "\(spec)")
            XCTAssertEqual(SurfaceSizing.shelfExtra(for: spec, in: layout, requested: 100), 0, "\(spec)")
        }
    }

    func testOfferedOnTopEdgeNotchesAndIslandsOnly() {
        XCTAssertTrue(ShelfHeight.offered(in: NotchGeometry.layout(for: laptop)))
        XCTAssertTrue(ShelfHeight.offered(in: NotchGeometry.layout(for: tall, prefersIsland: true)))
        XCTAssertTrue(ShelfHeight.offered(in: NotchGeometry.layout(for: tall, placement: .topLeft)))
        XCTAssertTrue(ShelfHeight.offered(in: NotchGeometry.layout(for: tall, placement: .topRight)))
        for placement: Placement in [.bottom, .left, .right, .floating] {
            let layout = NotchGeometry.layout(for: tall, placement: placement)
            XCTAssertFalse(ShelfHeight.offered(in: layout), "\(placement)")
            XCTAssertEqual(
                SurfaceSizing.rect(for: solo, in: layout, extraHeight: 100), SurfaceSizing.rect(for: solo, in: layout),
                "\(placement)")
        }
        // An island dragged off its spot opens like the orb, toward the middle of the screen.
        let moved = NotchGeometry.layout(
            for: tall, prefersIsland: true, islandCentre: CGPoint(x: 2800, y: 700))
        XCTAssertFalse(ShelfHeight.offered(in: moved))
    }

    func testPanelFitsTheTallestShelfAndItsNavPill() {
        for (screen, island) in [(laptop, false), (tall, false), (tall, true), (short, false)] {
            let layout = NotchGeometry.layout(for: screen, prefersIsland: island)
            let tallest = SurfaceSizing.rect(for: solo, in: layout, extraHeight: 5000)
            let pill = SurfaceSizing.navPillRect(for: tallest, placement: layout.anchor)
            XCTAssertTrue(layout.panelFrame.contains(tallest.union(pill)), "\(screen.frame)")
            XCTAssertTrue(screen.frame.contains(layout.panelFrame), "\(screen.frame)")
        }
    }

    func testDraggingFollowsThePointerWithinLimits() {
        XCTAssertEqual(ShelfHeight.dragged(from: 40, by: 25, maxExtra: 300), 65)
        XCTAssertEqual(ShelfHeight.dragged(from: 40, by: -100, maxExtra: 300), 0)
        XCTAssertEqual(ShelfHeight.dragged(from: 40, by: 1000, maxExtra: 300), 300)
        XCTAssertEqual(ShelfHeight.dragged(from: 0, by: 50, maxExtra: -10), 0)
    }

    func testSmallDragsSettleBackToTheDefault() {
        XCTAssertEqual(ShelfHeight.settled(ShelfHeight.snapDistance - 1), 0)
        XCTAssertEqual(ShelfHeight.settled(ShelfHeight.snapDistance), ShelfHeight.snapDistance)
        XCTAssertEqual(ShelfHeight.settled(180.4), 180)
        XCTAssertEqual(ShelfHeight.settled(-5), 0)
    }

    func testStoringRemovesDefaults() {
        let stored = ShelfHeight.storing(120, for: "agents", in: ["clipboard": 60])
        XCTAssertEqual(stored, ["clipboard": 60, "agents": 120])
        XCTAssertEqual(ShelfHeight.storing(0, for: "agents", in: stored), ["clipboard": 60])
        XCTAssertEqual(ShelfHeight.storing(-3, for: "clipboard", in: ["clipboard": 60]), [:])
    }

    func testReadingIgnoresBadValues() {
        XCTAssertEqual(ShelfHeight.extra(for: "agents", in: ["agents": 90]), 90)
        XCTAssertEqual(ShelfHeight.extra(for: "agents", in: [:]), 0)
        XCTAssertEqual(ShelfHeight.extra(for: "agents", in: ["agents": -20]), 0)
        XCTAssertEqual(ShelfHeight.extra(for: "agents", in: ["agents": .nan]), 0)
        XCTAssertEqual(ShelfHeight.extra(for: nil, in: ["agents": 90]), 0)
    }
}
