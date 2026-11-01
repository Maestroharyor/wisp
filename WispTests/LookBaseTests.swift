import XCTest

@testable import WispCore

final class LookBaseTests: XCTestCase {
    private var mine: Appearance {
        var look = Appearance.standard
        look.theme = .ember
        look.customSounds = ["done": "/Users/me/ding.aiff"]
        return look
    }

    private var neon: Appearance {
        var look = Appearance.standard
        look.theme = .midnight
        return look
    }

    func testAProfileLookRemembersTheUsersLookAndGivesItBack() {
        var state = LookBase()
        let shown = state.putOn(neon, over: mine)
        XCTAssertEqual(shown.theme, .midnight)
        XCTAssertEqual(shown.customSounds, mine.customSounds, "custom sounds stay")
        XCTAssertEqual(state.takeOff(), mine)
        XCTAssertNil(state.takeOff(), "given back once")
    }

    func testASecondProfileLookKeepsTheFirstBase() {
        var state = LookBase()
        let first = state.putOn(neon, over: mine)
        _ = state.putOn(Appearance.standard, over: first)
        XCTAssertEqual(state.takeOff(), mine)
    }

    func testAnEditByHandBecomesTheNewBase() {
        var state = LookBase()
        _ = state.putOn(neon, over: mine)
        state.editedByHand()
        XCTAssertNil(state.takeOff(), "the edited look stays")
    }

    func testRestoresTheSavedBase() {
        var state = LookBase(base: mine)
        XCTAssertEqual(state.takeOff(), mine)
    }
}
