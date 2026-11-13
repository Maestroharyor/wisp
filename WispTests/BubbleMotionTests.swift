import XCTest

@testable import WispCore

final class BubbleMotionTests: XCTestCase {
    func testTargetSplitsOneSidePerBubble() {
        XCTAssertEqual(BubbleSides.target(count: 0), .tucked)
        XCTAssertEqual(BubbleSides.target(count: 1), BubbleSides(first: 1, second: 0))
        XCTAssertEqual(BubbleSides.target(count: 2), BubbleSides(first: 1, second: 1))
        XCTAssertEqual(BubbleSides.target(count: 5), BubbleSides(first: 1, second: 1))
    }

    func testSidesReadByIndex() {
        let sides = BubbleSides(first: 0.25, second: 0.75)
        XCTAssertEqual(sides[0], 0.25)
        XCTAssertEqual(sides[1], 0.75)
        XCTAssertEqual(sides.total, 1)
    }

    func testSwapOnlyWhenASideShowsSomethingElse() {
        XCTAssertFalse(BubbleMotion.swapped(shown: [nil, nil], live: ["timer"]))
        XCTAssertFalse(BubbleMotion.swapped(shown: ["timer", nil], live: ["timer", "agent"]))
        XCTAssertTrue(BubbleMotion.swapped(shown: ["timer", nil], live: ["agent"]))
        XCTAssertTrue(BubbleMotion.swapped(shown: ["timer", "agent"], live: ["timer", "media"]))
        // A side that is merging away with nothing new for it isn't a swap.
        XCTAssertFalse(BubbleMotion.swapped(shown: ["timer", "agent"], live: ["timer"]))
    }

    func testShowingTakesLiveBubblesAndKeepsMergingOnes() {
        XCTAssertEqual(BubbleMotion.showing(shown: ["timer", "agent"], live: ["media"]), ["media", "agent"])
        XCTAssertEqual(
            BubbleMotion.showing(shown: [nil, nil], live: ["timer", "agent", "media"]), ["timer", "agent"])
        XCTAssertEqual(BubbleMotion.showing(shown: [nil, nil], live: [String]()), [nil, nil])
    }

    func testSettledForgetsSidesThatMergedBackIn() {
        let merged = BubbleMotion.settled(
            shown: ["timer", "agent"], live: ["timer"], split: BubbleSides(first: 1, second: 0))
        XCTAssertEqual(merged, ["timer", nil])
    }

    func testSettledKeepsASideStillOut() {
        let out = BubbleMotion.settled(
            shown: ["timer", "agent"], live: ["timer"], split: BubbleSides(first: 1, second: 0.5))
        XCTAssertEqual(out, ["timer", "agent"])
    }

    func testSettledWithNothingLiveLeavesNoGlyph() {
        // The shelf opened mid-merge: nothing live, both sides tucked, nothing left to draw.
        XCTAssertEqual(BubbleMotion.settled(shown: ["timer", "agent"], live: [], split: .tucked), [nil, nil])
    }

    func testShortShownReadsAsEmptySides() {
        XCTAssertFalse(BubbleMotion.swapped(shown: [String?](), live: ["timer", "agent"]))
        XCTAssertEqual(BubbleMotion.showing(shown: [String?](), live: ["timer"]), ["timer", nil])
        XCTAssertEqual(
            BubbleMotion.settled(shown: ["timer"], live: [String](), split: BubbleSides(first: 1, second: 1)),
            ["timer", nil])
    }

    func testSettledShowsLiveBubbles() {
        let live = BubbleMotion.settled(shown: [nil, nil], live: ["media", "agent"], split: .tucked)
        XCTAssertEqual(live, ["media", "agent"])
    }
}
