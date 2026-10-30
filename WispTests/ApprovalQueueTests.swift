import XCTest

@testable import WispCore

final class ApprovalQueueTests: XCTestCase {
    func testFrontStaysUntilAnswered() {
        var queue = ApprovalQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        XCTAssertEqual(queue.front, 1)
        queue.enqueue(3)
        XCTAssertEqual(queue.front, 1, "a newer request never replaces the card on show")
        queue.remove(1)
        XCTAssertEqual(queue.front, 2)
    }

    func testAnsweringOneBehindTheFrontKeepsTheFront() {
        var queue = ApprovalQueue<Int>()
        [1, 2, 3].forEach { queue.enqueue($0) }
        queue.remove(2)
        XCTAssertEqual(queue.items, [1, 3])
    }

    func testEnqueueIgnoresDuplicates() {
        var queue = ApprovalQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(1)
        XCTAssertEqual(queue.items.count, 1)
    }

    func testPositionLabel() {
        var queue = ApprovalQueue<String>()
        queue.enqueue("a")
        XCTAssertNil(queue.positionLabel, "no counter for a single request")
        queue.enqueue("b")
        XCTAssertEqual(queue.positionLabel, "1 of 2")
    }
}
