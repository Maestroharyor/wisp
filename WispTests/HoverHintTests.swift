import CoreGraphics
import XCTest

@testable import WispCore

final class HoverHintTests: XCTestCase {
    // A shelf surface 400x200 in its own space, y down.
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
    private let label = CGSize(width: 80, height: 18)

    func testDelayIsHalfASecond() {
        XCTAssertEqual(HoverHint.delay, .milliseconds(500))
    }

    func testKeepsThePreferredEdgeWhenThereIsRoom() {
        let anchor = CGRect(x: 160, y: 90, width: 20, height: 20)
        let above = HoverHint.placement(preferred: .top, anchor: anchor, label: label, bounds: bounds)
        XCTAssertEqual(above.edge, .top)
        XCTAssertEqual(above.center.x, 170)
        XCTAssertEqual(above.center.y, 90 - HoverHint.gap - 9)

        let below = HoverHint.placement(preferred: .bottom, anchor: anchor, label: label, bounds: bounds)
        XCTAssertEqual(below.edge, .bottom)
        XCTAssertEqual(below.center.y, 110 + HoverHint.gap + 9)
    }

    func testDropsBelowAViewNearTheTop() {
        // The agent detail header sits a few points under the surface's top edge.
        let anchor = CGRect(x: 160, y: 8, width: 20, height: 16)
        let placed = HoverHint.placement(preferred: .top, anchor: anchor, label: label, bounds: bounds)
        XCTAssertEqual(placed.edge, .bottom)
        XCTAssertEqual(placed.center.y, 24 + HoverHint.gap + 9)
    }

    func testRisesAboveAViewNearTheBottom() {
        let anchor = CGRect(x: 160, y: 180, width: 20, height: 16)
        let placed = HoverHint.placement(preferred: .bottom, anchor: anchor, label: label, bounds: bounds)
        XCTAssertEqual(placed.edge, .top)
    }

    func testPicksTheRoomierEdgeWhenNeitherFits() {
        let short = CGRect(x: 0, y: 0, width: 400, height: 40)
        let anchor = CGRect(x: 160, y: 10, width: 20, height: 24)
        let placed = HoverHint.placement(preferred: .top, anchor: anchor, label: label, bounds: short)
        XCTAssertEqual(placed.edge, .top)
        let lower = CGRect(x: 160, y: 4, width: 20, height: 24)
        XCTAssertEqual(HoverHint.placement(preferred: .top, anchor: lower, label: label, bounds: short).edge, .bottom)
    }

    func testClampsHorizontallyInsideTheBounds() {
        let left = CGRect(x: 2, y: 90, width: 20, height: 20)
        let placedLeft = HoverHint.placement(preferred: .top, anchor: left, label: label, bounds: bounds)
        XCTAssertEqual(placedLeft.center.x, HoverHint.inset + 40)

        let right = CGRect(x: 385, y: 90, width: 20, height: 20)
        let placedRight = HoverHint.placement(preferred: .top, anchor: right, label: label, bounds: bounds)
        XCTAssertEqual(placedRight.center.x, 400 - HoverHint.inset - 40)
    }

    func testALabelWiderThanTheBoundsStartsAtTheLeadingInset() {
        let wide = CGSize(width: 500, height: 18)
        let anchor = CGRect(x: 190, y: 90, width: 20, height: 20)
        let placed = HoverHint.placement(preferred: .top, anchor: anchor, label: wide, bounds: bounds)
        XCTAssertEqual(placed.center.x, HoverHint.inset + 250)
    }

    func testRespectsAnOffsetContainer() {
        let offset = CGRect(x: 100, y: 50, width: 200, height: 100)
        let anchor = CGRect(x: 100, y: 52, width: 20, height: 20)
        let placed = HoverHint.placement(preferred: .top, anchor: anchor, label: label, bounds: offset)
        XCTAssertEqual(placed.edge, .bottom)
        XCTAssertEqual(placed.center.x, 100 + HoverHint.inset + 40)
    }
}
