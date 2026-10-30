import CoreGraphics
import XCTest

@testable import WispCore

final class SurfaceSizingTests: XCTestCase {
    private let notched = NotchGeometry.layout(
        for: ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
        )
    )
    private let island = NotchGeometry.layout(
        for: ScreenMetrics(
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1056)
        ),
        prefersIsland: true
    )

    func testClosedAndPeek() {
        XCTAssertEqual(SurfaceSizing.rect(for: .closed, in: notched), notched.closedRect)
        XCTAssertEqual(SurfaceSizing.rect(for: .peek, in: notched), notched.peekRect)
    }

    func testCompactWingsOnNotch() {
        let narrow = SurfaceSizing.rect(for: .compact(wide: false), in: notched)
        let wide = SurfaceSizing.rect(for: .compact(wide: true), in: notched)
        XCTAssertEqual(narrow.width, notched.closedRect.width + 2 * ActivityMetrics.compactNotchWing)
        XCTAssertEqual(wide.width, notched.closedRect.width + 2 * ActivityMetrics.interactiveNotchWing)
        XCTAssertEqual(narrow.height, notched.closedRect.height)
    }

    func testCompactIslandUsesFixedWidths() {
        XCTAssertEqual(SurfaceSizing.rect(for: .compact(wide: false), in: island).width, 150)
        XCTAssertEqual(SurfaceSizing.rect(for: .compact(wide: true), in: island).width, 240)
    }

    func testMediumCardSitsBelowTheNotch() {
        let medium = SurfaceSizing.rect(for: .medium, in: notched)
        XCTAssertEqual(medium.height, notched.closedRect.height + ActivityMetrics.cardContentHeight + 12)
        XCTAssertGreaterThan(medium.width, SurfaceSizing.rect(for: .compact(wide: true), in: notched).width - 1)
    }

    func testHomeWidthGrowsWithWidgetsAndRespectsMinimum() {
        let one = SurfaceSizing.rect(for: .home(contentWidth: 180, editing: false), in: notched)
        let two = SurfaceSizing.rect(for: .home(contentWidth: 385, editing: false), in: notched)
        let three = SurfaceSizing.rect(for: .home(contentWidth: 590, editing: false), in: notched)
        XCTAssertEqual(one.width, 451)
        XCTAssertGreaterThan(two.width, one.width)
        XCTAssertGreaterThan(three.width, two.width)
        // Notch style: housing height + 10 above, shared content height, 16 below; minimum width 451.
        XCTAssertEqual(one.height, 32 + 10 + SurfaceSizing.shelfContentHeight + 16)
        XCTAssertEqual(
            SurfaceSizing.rect(for: .home(contentWidth: 0, editing: false), in: notched).width, 451)
    }

    func testEditingAddsThePickerRow() {
        let normal = SurfaceSizing.rect(for: .home(contentWidth: 385, editing: false), in: notched)
        let editing = SurfaceSizing.rect(for: .home(contentWidth: 385, editing: true), in: notched)
        XCTAssertEqual(editing.height - normal.height, SurfaceSizing.pickerRowHeight)
    }

    func testIslandShelfUsesIslandMinimum() {
        XCTAssertEqual(
            SurfaceSizing.rect(for: .home(contentWidth: 180, editing: false), in: island).width, 405)
    }

    func testSurfacesNeverExceedTheLargestAllowed() {
        let huge = SurfaceSizing.rect(for: .home(contentWidth: 5000, editing: true), in: notched)
        XCTAssertLessThanOrEqual(huge.width, NotchSizes.standard.maxSurface.width)
        let tray = SurfaceSizing.rect(for: .tray(items: 200), in: notched)
        XCTAssertLessThanOrEqual(tray.width, NotchSizes.standard.maxSurface.width)
    }

    func testTrayLeavesRoomForTheDropCardAndHeaderActions() {
        let two = SurfaceSizing.rect(for: .tray(items: 2), in: notched)
        let six = SurfaceSizing.rect(for: .tray(items: 6), in: notched)
        let insets = ShellMetrics.shelfInsets(notchStyle: true, notchHeight: notched.closedRect.height)
        XCTAssertEqual(two.width - insets.leading - insets.trailing, SurfaceSizing.trayMinimumContentWidth)
        XCTAssertEqual(six.width - insets.leading - insets.trailing, 7 * SurfaceSizing.trayItemWidth)
    }

    func testNavPillHangsBelowTheSurface() {
        let surface = SurfaceSizing.rect(for: .home(contentWidth: 180, editing: false), in: notched)
        let pill = SurfaceSizing.navPillRect(below: surface)
        XCTAssertEqual(pill.maxY, surface.minY - SurfaceSizing.navPillGap)
        XCTAssertEqual(pill.midX, surface.midX)
    }

    func testEveryShelfPageSharesOneHeight() {
        let pages: [SurfaceSpec] = [
            .home(contentWidth: 180, editing: false), .home(contentWidth: 800, editing: false),
            .tray(items: 0), .tray(items: 30), .media, .widgetGrid(count: 3, rows: 2), .widgetGrid(count: 30, rows: 1),
            .widgetSolo(wide: false), .widgetSolo(wide: true),
            .dropTiles(extra: 0), .dropTiles(extra: 2),
        ]
        let heights = Set(pages.map { SurfaceSizing.rect(for: $0, in: notched).height })
        XCTAssertEqual(heights, [32 + 10 + SurfaceSizing.shelfContentHeight + 16])
    }

    func testWidgetGridAndMediaPageWidths() {
        XCTAssertEqual(SurfaceSizing.rect(for: .widgetGrid(count: 60, rows: 1), in: notched).width, 900)
        XCTAssertEqual(SurfaceSizing.rect(for: .media, in: notched).width, 48 + SurfaceSizing.mediaPageWidth + 48)
    }

    func testBubblesSitRightThenLeftOfThePillAsCircles() {
        let pill = SurfaceSizing.rect(for: .compact(wide: false), in: notched)
        let bubbles = SurfaceSizing.bubbleRects(beside: pill, count: 2)
        XCTAssertEqual(bubbles.count, 2)
        XCTAssertEqual(bubbles[0].width, pill.height)
        XCTAssertEqual(bubbles[0].height, pill.height)
        XCTAssertEqual(bubbles[0].minX, pill.maxX + SurfaceSizing.bubbleGap)
        XCTAssertEqual(bubbles[1].maxX, pill.minX - SurfaceSizing.bubbleGap)
        XCTAssertEqual(bubbles[0].midY, pill.midY)
    }

    func testNoBubblesAndAtMostTwo() {
        let pill = SurfaceSizing.rect(for: .compact(wide: false), in: notched)
        XCTAssertTrue(SurfaceSizing.bubbleRects(beside: pill, count: 0).isEmpty)
        XCTAssertEqual(SurfaceSizing.bubbleRects(beside: pill, count: 5).count, 2)
    }

    func testFirstBubbleCanSitOnTheLeft() {
        let pill = CGRect(x: 100, y: 0, width: 200, height: 32)
        let rects = SurfaceSizing.bubbleRects(beside: pill, count: 2, firstOnLeft: true)
        XCTAssertEqual(rects.first?.maxX, pill.minX - SurfaceSizing.bubbleGap)
        XCTAssertEqual(rects.last?.minX, pill.maxX + SurfaceSizing.bubbleGap)
    }

    func testDropActionTilesWidenTheShelfUpToTwo() {
        let four = SurfaceSizing.rect(for: .dropTiles(extra: 0), in: notched).width
        let six = SurfaceSizing.rect(for: .dropTiles(extra: 2), in: notched).width
        XCTAssertEqual(six - four, 2 * (SurfaceSizing.tileSize + SurfaceSizing.tileSpacing))
        XCTAssertEqual(SurfaceSizing.rect(for: .dropTiles(extra: 9), in: notched).width, six)
    }
}
