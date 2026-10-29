import XCTest

@testable import WispCore

final class ActivityQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testEmptyQueueShowsNothing() {
        XCTAssertNil(ActivityQueue<String>().current(now: now))
    }

    func testTransientPreemptsStickyThenHandsBack() {
        var queue = ActivityQueue<String>()
        queue.post(id: "media", priority: 10, duration: nil, payload: "media", now: now)
        queue.post(id: "volume", priority: 50, duration: 1.5, payload: "volume", now: now)
        XCTAssertEqual(queue.current(now: now)?.payload, "volume")
        XCTAssertEqual(queue.current(now: now.addingTimeInterval(2))?.payload, "media")
    }

    func testSameIdUpdatesInPlaceAndExtendsExpiry() {
        var queue = ActivityQueue<Int>()
        queue.post(id: "volume", priority: 50, duration: 1.5, payload: 40, now: now)
        queue.post(id: "volume", priority: 50, duration: 1.5, payload: 60, now: now.addingTimeInterval(1))
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertEqual(queue.current(now: now.addingTimeInterval(2))?.payload, 60)
    }

    func testEqualPriorityPrefersMostRecent() {
        var queue = ActivityQueue<String>()
        queue.post(id: "a", priority: 50, duration: 5, payload: "a", now: now)
        queue.post(id: "b", priority: 50, duration: 5, payload: "b", now: now.addingTimeInterval(0.1))
        XCTAssertEqual(queue.current(now: now.addingTimeInterval(0.2))?.payload, "b")
    }

    func testPruneDropsExpiredAndKeepsSticky() {
        var queue = ActivityQueue<String>()
        queue.post(id: "media", priority: 10, duration: nil, payload: "m", now: now)
        queue.post(id: "hud", priority: 50, duration: 1, payload: "h", now: now)
        queue.prune(now: now.addingTimeInterval(5))
        XCTAssertEqual(Set(queue.entries.keys), ["media"])
    }

    func testNextExpiryAndRemove() {
        var queue = ActivityQueue<String>()
        queue.post(id: "a", priority: 1, duration: 3, payload: "a", now: now)
        queue.post(id: "b", priority: 1, duration: 1, payload: "b", now: now)
        XCTAssertEqual(queue.nextExpiry(after: now), now.addingTimeInterval(1))
        queue.remove(id: "b")
        XCTAssertEqual(queue.nextExpiry(after: now), now.addingTimeInterval(3))
    }
}
