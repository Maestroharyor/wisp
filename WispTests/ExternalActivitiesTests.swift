import XCTest

@testable import WispCore

final class ExternalActivitiesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 50_000)

    private func start(_ id: String, _ title: String = "Job", progress: Double? = nil) -> ExternalActivityAction {
        .start(ExternalActivity(id: id, title: title, symbol: ExternalActivity.defaultSymbol, progress: progress))
    }

    func testStartShowsTheActivity() {
        var board = ExternalActivities()
        board.apply(start("a", "Build"), now: now)
        XCTAssertEqual(board.current(now: now)?.title, "Build")
        XCTAssertEqual(board.expiry(now: now), now + ExternalActivities.lifetime)
    }

    func testUpdateChangesOnlyWhatItNames() {
        var board = ExternalActivities()
        board.apply(start("a", "Build", progress: 0.1), now: now)
        board.apply(
            .update(ExternalActivityUpdate(id: "a", title: nil, symbol: "hammer.fill", progress: 0.6)), now: now)
        let current = board.current(now: now)
        XCTAssertEqual(current?.title, "Build")
        XCTAssertEqual(current?.symbol, "hammer.fill")
        XCTAssertEqual(current?.progress, 0.6)
    }

    func testUpdateWithATitleStartsAnUnknownActivity() {
        var board = ExternalActivities()
        XCTAssertFalse(
            board.apply(.update(ExternalActivityUpdate(id: "a", title: nil, symbol: nil, progress: 0.5)), now: now))
        XCTAssertNil(board.current(now: now))
        XCTAssertTrue(
            board.apply(.update(ExternalActivityUpdate(id: "a", title: "Sync", symbol: nil, progress: 0.5)), now: now))
        XCTAssertEqual(board.current(now: now)?.title, "Sync")
        XCTAssertEqual(board.current(now: now)?.symbol, ExternalActivity.defaultSymbol)
    }

    func testEndRemovesItAndTheNextOneShows() {
        var board = ExternalActivities()
        board.apply(start("a", "First"), now: now)
        board.apply(start("b", "Second"), now: now + 1)
        XCTAssertEqual(board.current(now: now + 1)?.id, "b")
        board.apply(.end(id: "b"), now: now + 2)
        XCTAssertEqual(board.current(now: now + 2)?.id, "a")
        board.apply(.end(id: "a"), now: now + 3)
        XCTAssertNil(board.current(now: now + 3))
    }

    func testTheMostRecentlyTouchedActivityShows() {
        var board = ExternalActivities()
        board.apply(start("a"), now: now)
        board.apply(start("b"), now: now + 1)
        board.apply(.update(ExternalActivityUpdate(id: "a", title: nil, symbol: nil, progress: 0.2)), now: now + 2)
        XCTAssertEqual(board.current(now: now + 2)?.id, "a")
    }

    // A script that dies without sending `end` must not keep the notch busy.
    func testActivitiesExpireUnlessUpdated() {
        var board = ExternalActivities()
        board.apply(start("a"), now: now)
        let almost = now + ExternalActivities.lifetime - 1
        board.apply(.update(ExternalActivityUpdate(id: "a", title: nil, symbol: nil, progress: 0.3)), now: almost)
        XCTAssertNotNil(board.current(now: almost + ExternalActivities.lifetime - 1))
        XCTAssertNil(board.current(now: almost + ExternalActivities.lifetime))
        board.prune(now: almost + ExternalActivities.lifetime)
        XCTAssertTrue(board.isEmpty)
    }

    func testExpiryIsTheSoonestOfTheLiveOnes() {
        var board = ExternalActivities()
        board.apply(start("a"), now: now)
        board.apply(start("b"), now: now + 10)
        XCTAssertEqual(board.expiry(now: now + 10), now + ExternalActivities.lifetime)
        XCTAssertNil(ExternalActivities().expiry(now: now))
    }

    func testTheOldestIsDroppedPastTheLimit() {
        var board = ExternalActivities()
        for index in 0...ExternalActivities.limit {
            board.apply(start("job\(index)"), now: now + TimeInterval(index))
        }
        XCTAssertEqual(board.count, ExternalActivities.limit)
        let last = now + TimeInterval(ExternalActivities.limit)
        board.apply(.end(id: "job\(ExternalActivities.limit)"), now: last)
        for index in 1..<ExternalActivities.limit {
            board.apply(.end(id: "job\(index)"), now: last)
        }
        // job0 was dropped, so nothing is left once the others end.
        XCTAssertNil(board.current(now: last))
    }

    func testRemembersWhoPostedIt() {
        var board = ExternalActivities()
        board.apply(start("a", "Build"), from: .command, now: now)
        XCTAssertEqual(board.current(now: now)?.source, .command)
        // An update from somewhere else takes over: that's who last spoke for it.
        board.apply(
            .update(ExternalActivityUpdate(id: "a", title: nil, symbol: nil, progress: 0.5)), from: .shortcut, now: now)
        XCTAssertEqual(board.current(now: now)?.source, .shortcut)
        XCTAssertEqual(board.current(now: now)?.progress, 0.5)
    }

    func testSourceIsUnknownWhenNotGiven() {
        var board = ExternalActivities()
        board.apply(start("a"), now: now)
        XCTAssertNil(board.current(now: now)?.source)
    }

    func testSourceLabels() {
        XCTAssertEqual(ExternalActivitySource.link.label, "From a wisp:// link")
        XCTAssertEqual(ExternalActivitySource.command.label, "From the wisp command")
        XCTAssertEqual(ExternalActivitySource.shortcut.label, "From Shortcuts")
    }
}
