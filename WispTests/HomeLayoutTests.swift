import CoreGraphics
import XCTest

@testable import WispCore

final class HomeLayoutTests: XCTestCase {
    func testHoldsAtMostFour() {
        var layout = HomeLayout()
        for id in ["a", "b", "c", "d"] { XCTAssertTrue(layout.add(id, size: .small)) }
        XCTAssertFalse(layout.add("e", size: .small))
        XCTAssertFalse(layout.add("a", size: .large), "no duplicates")
        XCTAssertEqual(layout.ids, ["a", "b", "c", "d"])
        XCTAssertTrue(layout.isFull)
    }

    func testRemoveMoveAndResize() {
        var layout = HomeLayout(slots: [
            .init(id: "a", size: .small), .init(id: "b", size: .small), .init(id: "c", size: .small),
        ])
        layout.move("c", before: "a")
        XCTAssertEqual(layout.ids, ["c", "a", "b"])
        layout.move("c", before: "b")
        XCTAssertEqual(layout.ids, ["a", "c", "b"])
        layout.resize("a", to: .large)
        XCTAssertEqual(layout.slots.first?.size, .large)
        layout.remove("c")
        XCTAssertEqual(layout.ids, ["a", "b"])
        XCTAssertFalse(layout.contains("c"))
    }

    func testSizeCyclesAndWidths() {
        XCTAssertEqual(WidgetSize.small.next(in: WidgetSize.standard), .medium)
        XCTAssertEqual(WidgetSize.medium.next(in: WidgetSize.standard), .large)
        XCTAssertEqual(WidgetSize.large.next(in: WidgetSize.standard), .small)
    }

    func testUnknownSizeReadsAsLarge() throws {
        let layout = try JSONDecoder().decode(
            HomeLayout.self, from: Data(#"{"slots":[{"id":"agents","size":"giant"},{"id":"x","size":"wide"}]}"#.utf8))
        XCTAssertEqual(layout.slots.map(\.size), [.large, .wide])
        XCTAssertLessThan(WidgetSize.small.width, WidgetSize.medium.width)
        XCTAssertLessThan(WidgetSize.medium.width, WidgetSize.large.width)
    }

    func testContentWidthIncludesDividers() {
        let layout = HomeLayout(slots: [.init(id: "a", size: .small), .init(id: "b", size: .large)])
        XCTAssertEqual(
            layout.contentWidth, WidgetSize.small.width + WidgetSize.large.width + HomeLayout.dividerSpacing)
        XCTAssertEqual(HomeLayout().contentWidth, 0)
        XCTAssertEqual(
            HomeLayout.contentWidth(of: [.small, .medium, .large]),
            WidgetSize.small.width + WidgetSize.medium.width + WidgetSize.large.width + 2 * HomeLayout.dividerSpacing)
    }

    func testCodableRoundTrip() throws {
        let layout = HomeLayout(slots: [.init(id: "a", size: .medium)])
        let data = try JSONEncoder().encode(layout)
        XCTAssertEqual(try JSONDecoder().decode(HomeLayout.self, from: data), layout)
    }

    func testSampleHistoryKeepsTheNewest() {
        var history = SampleHistory(capacity: 3)
        [0.1, 0.2, 0.3, 0.4].forEach { history.append($0) }
        XCTAssertEqual(history.values, [0.2, 0.3, 0.4])
        XCTAssertEqual(history.latest, 0.4)
        XCTAssertNil(SampleHistory(capacity: 2).latest)
    }
}
