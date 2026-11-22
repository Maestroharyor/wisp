import XCTest

@testable import WispCore

final class RingTipsTests: XCTestCase {
    func testStepsTickOffInAnyOrder() {
        var tips = RingTips()
        XCTAssertEqual(tips.next, .open)
        XCTAssertTrue(tips.mark(.search))
        XCTAssertFalse(tips.mark(.search), "a second time changes nothing")
        XCTAssertEqual(tips.next, .open)
        RingTips.Step.allCases.forEach { tips.mark($0) }
        XCTAssertTrue(tips.isComplete)
        XCTAssertNil(tips.next)
        tips.reset()
        XCTAssertTrue(tips.done.isEmpty)
    }

    func testTheListSurvivesSavingAndUnknownSteps() throws {
        var tips = RingTips()
        tips.mark(.convert)
        let data = try JSONEncoder().encode(tips)
        XCTAssertEqual(try JSONDecoder().decode(RingTips.self, from: data).done, [.convert])
        let read = try JSONDecoder().decode(RingTips.self, from: Data(#"{"done": ["open", "teleport"]}"#.utf8))
        XCTAssertEqual(read.done, [.open])
        XCTAssertTrue(try JSONDecoder().decode(RingTips.self, from: Data("{}".utf8)).done.isEmpty)
    }
}

final class RingTrailTests: XCTestCase {
    func testTheTrailTurnsTheShortWayRound() {
        XCTAssertEqual(RingGeometry.shortTurn(from: 350, to: 10), 20)
        XCTAssertEqual(RingGeometry.shortTurn(from: 10, to: 350), -20)
        XCTAssertEqual(RingGeometry.shortTurn(from: 720, to: 90), 90, "an unwrapped heading still turns the short way")
        XCTAssertEqual(RingGeometry.shortTurn(from: 0, to: 180), 180)
        XCTAssertEqual(RingGeometry.shortTurn(from: 30, to: 30), 0)
    }
}
