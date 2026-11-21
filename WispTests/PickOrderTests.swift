import XCTest

@testable import WispCore

final class PickOrderTests: XCTestCase {
    func testNewPicksGoOnTheEnd() {
        XCTAssertEqual(
            PickOrder.update(["c", "a"], selection: ["a", "b", "c"], listOrder: ["a", "b", "c"]), ["c", "a", "b"])
    }

    func testUnpickedItemsLeaveAndTheRestKeepTheirPlace() {
        XCTAssertEqual(
            PickOrder.update(["c", "a", "b"], selection: ["c", "b"], listOrder: ["a", "b", "c"]), ["c", "b"])
    }

    func testSeveralPickedAtOnceFollowTheList() {
        // ⇧-click or ⌘A adds a run at once; the run keeps the list's order.
        XCTAssertEqual(
            PickOrder.update(["d"], selection: ["a", "b", "c", "d"], listOrder: ["a", "b", "c", "d"]),
            ["d", "a", "b", "c"])
    }

    func testAnEmptySelectionClearsTheOrder() {
        XCTAssertEqual(PickOrder.update(["a", "b"], selection: [], listOrder: ["a", "b"]), [])
    }

    func testPicksMissingFromTheListStillCount() {
        // A search can hide a picked item without unpicking it.
        XCTAssertEqual(PickOrder.update(["z"], selection: ["z", "a"], listOrder: ["a"]), ["z", "a"])
    }
}
