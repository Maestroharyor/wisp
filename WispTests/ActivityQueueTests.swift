import XCTest

@testable import WispCore

final class ActivityQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testEmptyQueueShowsNothing() {
        XCTAssertNil(ActivityQueue<String>().current(now: now))
    }

    func testLiveFindsAnEntryHiddenBehindTheWinner() {
        var queue = ActivityQueue<String>()
        queue.post(id: "media", priority: 10, duration: nil, payload: "media", now: now)
        queue.post(id: "agent", priority: 15, duration: nil, payload: "agent", now: now)
        queue.post(id: "notice", priority: 45, duration: 1, payload: "notice", now: now)
        XCTAssertEqual(queue.live(id: "media", now: now)?.payload, "media")
        XCTAssertNil(queue.live(id: "notice", now: now.addingTimeInterval(2)))
        XCTAssertNil(queue.live(id: "missing", now: now))
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

    // MARK: Arrangement (main pill plus bubbles)

    private let capable: Set<String> = ["media", "timer", "agent", "meeting"]

    private func sticky(_ ids: [(String, Int)]) -> ActivityQueue<String> {
        var queue = ActivityQueue<String>()
        for (offset, item) in ids.enumerated() {
            queue.post(
                id: item.0, priority: item.1, duration: nil, payload: item.0,
                now: now.addingTimeInterval(Double(offset)))
        }
        return queue
    }

    func testArrangementPutsHighestInThePillAndTheRestInBubblesByPriority() {
        let queue = sticky([("media", 10), ("timer", 20), ("agent", 15)])
        let arrangement = queue.arrangement(now: now, pinned: nil, bubbleIDs: capable, limit: 2)
        XCTAssertEqual(arrangement.primary?.id, "timer")
        XCTAssertEqual(arrangement.bubbles.map(\.id), ["agent", "media"])
    }

    func testArrangementKeepsAtMostTheLimit() {
        let queue = sticky([("media", 10), ("timer", 20), ("agent", 15), ("meeting", 44)])
        let arrangement = queue.arrangement(now: now, pinned: nil, bubbleIDs: capable, limit: 2)
        XCTAssertEqual(arrangement.primary?.id, "meeting")
        XCTAssertEqual(arrangement.bubbles.map(\.id), ["timer", "agent"])
    }

    func testPinnedBubbleTakesThePillAndTheWinnerBecomesABubble() {
        let queue = sticky([("media", 10), ("timer", 20)])
        let arrangement = queue.arrangement(now: now, pinned: "media", bubbleIDs: capable, limit: 2)
        XCTAssertEqual(arrangement.primary?.id, "media")
        XCTAssertEqual(arrangement.bubbles.map(\.id), ["timer"])
    }

    func testHUDTakesThePillOverAPinAndBubblesStay() {
        var queue = sticky([("media", 10), ("timer", 20)])
        queue.post(id: "level", priority: 70, duration: 1.5, payload: "level", now: now)
        let arrangement = queue.arrangement(now: now, pinned: "media", bubbleIDs: capable, limit: 2)
        XCTAssertEqual(arrangement.primary?.id, "level")
        XCTAssertEqual(arrangement.bubbles.map(\.id), ["timer", "media"])
    }

    func testEndedPinIsIgnored() {
        let queue = sticky([("media", 10), ("timer", 20)])
        let arrangement = queue.arrangement(now: now, pinned: "agent", bubbleIDs: capable, limit: 2)
        XCTAssertEqual(arrangement.primary?.id, "timer")
        XCTAssertEqual(arrangement.bubbles.map(\.id), ["media"])
    }

    func testOnlyCapableActivitiesBecomeBubbles() {
        var queue = sticky([("media", 10), ("tray", 30)])
        queue.post(id: "notice", priority: 45, duration: 2, payload: "notice", now: now)
        let arrangement = queue.arrangement(now: now, pinned: nil, bubbleIDs: capable, limit: 2)
        XCTAssertEqual(arrangement.primary?.id, "notice")
        XCTAssertEqual(arrangement.bubbles.map(\.id), ["media"])
    }

    func testSingleActivityHasNoBubbles() {
        let arrangement = sticky([("media", 10)]).arrangement(now: now, pinned: nil, bubbleIDs: capable, limit: 2)
        XCTAssertEqual(arrangement.primary?.id, "media")
        XCTAssertTrue(arrangement.bubbles.isEmpty)
    }
}
