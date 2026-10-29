import CoreGraphics
import XCTest

@testable import WispCore

final class WidgetGridTests: XCTestCase {
    func testColumnsFillRowsTopToBottom() {
        XCTAssertEqual(WidgetGrid.columns(count: 0, rows: 2), 0)
        XCTAssertEqual(WidgetGrid.columns(count: 1, rows: 2), 1)
        XCTAssertEqual(WidgetGrid.columns(count: 2, rows: 2), 1)
        XCTAssertEqual(WidgetGrid.columns(count: 3, rows: 2), 2)
        XCTAssertEqual(WidgetGrid.columns(count: 8, rows: 2), 4)
        XCTAssertEqual(WidgetGrid.columns(count: 5, rows: 1), 5)
    }

    func testRowsAreClampedToOneOrTwo() {
        XCTAssertEqual(WidgetGrid.columns(count: 4, rows: 0), 4)
        XCTAssertEqual(WidgetGrid.columns(count: 4, rows: 9), 2)
    }

    func testTwoRowsFitTheSharedShelfHeight() {
        XCTAssertLessThanOrEqual(2 * WidgetGrid.cellHeight + WidgetGrid.rowSpacing, SurfaceSizing.shelfContentHeight)
    }

    func testContentWidth() {
        XCTAssertEqual(WidgetGrid.contentWidth(count: 0, rows: 2), 0)
        XCTAssertEqual(WidgetGrid.contentWidth(count: 1, rows: 2), WidgetGrid.cellWidth)
        XCTAssertEqual(
            WidgetGrid.contentWidth(count: 5, rows: 2), 3 * WidgetGrid.cellWidth + 2 * WidgetGrid.columnSpacing)
    }

    func testMove() {
        XCTAssertEqual(WidgetGrid.move(["a", "b", "c", "d"], item: "d", before: "b"), ["a", "d", "b", "c"])
        XCTAssertEqual(WidgetGrid.move(["a", "b", "c", "d"], item: "a", before: "c"), ["b", "a", "c", "d"])
        XCTAssertEqual(WidgetGrid.move(["a", "b"], item: "a", before: "a"), ["a", "b"])
        XCTAssertEqual(WidgetGrid.move(["a", "b"], item: "x", before: "a"), ["a", "b"], "unknown item")
        XCTAssertEqual(
            WidgetGrid.move(["a", "b", "c"], item: "a", before: "x"), ["b", "c", "a"], "unknown target: to end")
    }

    func testMergeKeepsSavedOrderAndFollowsEnabled() {
        XCTAssertEqual(WidgetGrid.merge(order: ["c", "a"], enabled: ["a", "b", "c"]), ["c", "a", "b"])
        XCTAssertEqual(WidgetGrid.merge(order: ["c", "x", "a"], enabled: ["a", "c"]), ["c", "a"])
        XCTAssertEqual(WidgetGrid.merge(order: [], enabled: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(WidgetGrid.merge(order: ["a", "a"], enabled: ["a"]), ["a"])
    }
}

final class WidgetPageSizingTests: XCTestCase {
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

    func testSmallGridUsesTheShelfMinimumWidth() {
        XCTAssertEqual(
            SurfaceSizing.rect(for: .widgetGrid(count: 2, rows: 2), in: notched).width,
            ShellMetrics.shelfMinimumWidth(notchStyle: true))
        XCTAssertEqual(
            SurfaceSizing.rect(for: .widgetGrid(count: 0, rows: 2), in: island).width,
            ShellMetrics.shelfMinimumWidth(notchStyle: false))
    }

    func testWideGridGrowsWithColumns() {
        let rect = SurfaceSizing.rect(for: .widgetGrid(count: 8, rows: 1), in: notched)
        XCTAssertEqual(rect.width, 48 + WidgetGrid.contentWidth(count: 8, rows: 1) + 48)
    }

    func testSoloWidgetUsesTheSoloCardWidth() {
        let notchSolo = SurfaceSizing.rect(for: .widgetSolo, in: notched)
        XCTAssertEqual(
            notchSolo.width,
            max(
                48 + ShellMetrics.soloCardWidth(notchStyle: true) + 48, ShellMetrics.shelfMinimumWidth(notchStyle: true)
            ))
        let islandSolo = SurfaceSizing.rect(for: .widgetSolo, in: island)
        XCTAssertEqual(
            islandSolo.width,
            max(
                16 + ShellMetrics.soloCardWidth(notchStyle: false) + 16,
                ShellMetrics.shelfMinimumWidth(notchStyle: false)))
    }

    func testGridAndSoloKeepTheShelfHeight() {
        let home = SurfaceSizing.rect(for: .home(contentWidth: 400, editing: false), in: notched).height
        XCTAssertEqual(SurfaceSizing.rect(for: .widgetGrid(count: 5, rows: 2), in: notched).height, home)
        XCTAssertEqual(SurfaceSizing.rect(for: .widgetSolo, in: notched).height, home)
    }
}
