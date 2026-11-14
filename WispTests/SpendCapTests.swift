import XCTest

@testable import WispCore

final class SpendCapTests: XCTestCase {
    func testOffMeansNoCrossing() {
        var caps = SpendCap()
        XCTAssertNil(caps.check(session: "s", cost: 50, cap: nil))
        XCTAssertNil(caps.check(session: "s", cost: nil, cap: 5))
    }

    func testCrossesOnceAndHoldsUntilAChoice() {
        var caps = SpendCap()
        XCTAssertNil(caps.check(session: "s", cost: 4.99, cap: 5))
        XCTAssertEqual(caps.check(session: "s", cost: 5.2, cap: 5), SpendCap.Crossing(limit: 5, raise: 10))
        XCTAssertTrue(caps.isHeld("s"))
        XCTAssertNil(caps.check(session: "s", cost: 6, cap: 5))
        XCTAssertFalse(caps.isHeld("other"))
    }

    func testKeepGoingStopsAskingForThatSession() {
        var caps = SpendCap()
        _ = caps.check(session: "s", cost: 5, cap: 5)
        caps.keepGoing("s")
        XCTAssertFalse(caps.isHeld("s"))
        XCTAssertNil(caps.check(session: "s", cost: 50, cap: 5))
        XCTAssertNotNil(caps.check(session: "t", cost: 5, cap: 5))
    }

    func testRaiseAsksAgainAtTheNewLimit() {
        var caps = SpendCap()
        _ = caps.check(session: "s", cost: 5, cap: 5)
        caps.raise("s", to: 10)
        XCTAssertFalse(caps.isHeld("s"))
        XCTAssertNil(caps.check(session: "s", cost: 9, cap: 5))
        XCTAssertEqual(caps.check(session: "s", cost: 10.5, cap: 5), SpendCap.Crossing(limit: 10, raise: 15))
    }

    func testStopAsksAgainOnlyAfterTheNextPrompt() {
        var caps = SpendCap()
        _ = caps.check(session: "s", cost: 5, cap: 5)
        caps.stop("s")
        XCTAssertFalse(caps.isHeld("s"))
        // The interrupted request's cost arrives late; it doesn't ask again.
        XCTAssertNil(caps.check(session: "s", cost: 5.4, cap: 5))
        caps.newTurn("s")
        XCTAssertNotNil(caps.check(session: "s", cost: 5.5, cap: 5))
    }

    func testAChangedCapAppliesToSessionsNotYetRaised() {
        var caps = SpendCap()
        XCTAssertNil(caps.check(session: "s", cost: 6, cap: 10))
        XCTAssertNotNil(caps.check(session: "s", cost: 6, cap: 5))
    }

    func testForgetClearsASession() {
        var caps = SpendCap()
        _ = caps.check(session: "s", cost: 5, cap: 5)
        caps.forget("s")
        XCTAssertFalse(caps.isHeld("s"))
        XCTAssertNotNil(caps.check(session: "s", cost: 5, cap: 5))
    }

    func testCardText() {
        XCTAssertEqual(SpendCap.title(limit: 5, estimated: false), "Session reached $5")
        XCTAssertEqual(SpendCap.title(limit: 7.5, estimated: true), "Session reached about $7.50")
        XCTAssertEqual(SpendCap.raiseTitle(10), "Raise to $10")
    }
}
