import XCTest

@testable import WispCore

final class FormFactorTests: XCTestCase {
    func testPlacementsMapToForms() {
        XCTAssertEqual(FormFactor(placement: .top), .notch)
        XCTAssertEqual(FormFactor(placement: .topLeft), .corner)
        XCTAssertEqual(FormFactor(placement: .topRight), .corner)
        XCTAssertEqual(FormFactor(placement: .bottom), .bottom)
        XCTAssertEqual(FormFactor(placement: .left), .side)
        XCTAssertEqual(FormFactor(placement: .right), .side)
        XCTAssertEqual(FormFactor(placement: .floating), .orb)
        for form in FormFactor.allCases {
            guard let placement = form.placement else { continue }
            XCTAssertEqual(FormFactor(placement: placement), form)
        }
        // The window isn't a place on a display.
        XCTAssertNil(FormFactor.window.placement)
    }

    func testIslandMacsHaveNoNotchForm() {
        XCTAssertFalse(FormFactor.available(systemIsland: true).contains(.notch))
        XCTAssertEqual(FormFactor.available(systemIsland: false), FormFactor.allCases)
    }

    func testCyclingWrapsAndSkipsTheNotchOnIslandMacs() {
        XCTAssertEqual(FormFactor.orb.next(systemIsland: false), .window)
        XCTAssertEqual(FormFactor.window.next(systemIsland: false), .notch)
        XCTAssertEqual(FormFactor.window.next(systemIsland: true), .corner)
        XCTAssertEqual(FormFactor.notch.next(systemIsland: true), .corner)
    }

    func testTheWindowIsOfferedEverywhere() {
        XCTAssertEqual(FormFactor.available(systemIsland: true).last, .window)
        XCTAssertEqual(FormFactor.available(systemIsland: false).last, .window)
    }

    func testPickingTheWindowLeavesTheShellsPlacementAlone() {
        var state = OrbPlacements(overrides: ["a": "left"], returns: ["a": ""], standard: .top)
        state.set(.window, for: "a")
        XCTAssertEqual(state.overrides, ["a": "left"])
        XCTAssertEqual(state.returns, ["a": ""])
    }

    func testSwitchingToTheOrbRemembersTheWayBack() {
        var state = OrbPlacements(overrides: ["a": "left"], returns: [:], standard: .top)
        state.set(.orb, for: "a")
        XCTAssertEqual(state.placement(for: "a"), .floating)
        state.dock("a")
        XCTAssertEqual(state.placement(for: "a"), .left)
    }

    func testSwitchingFormsForgetsTheOrbsWayBack() {
        var state = OrbPlacements(overrides: ["a": "left"], returns: [:], standard: .top)
        state.set(.orb, for: "a")
        state.set(.bottom, for: "a")
        XCTAssertEqual(state.placement(for: "a"), .bottom)
        XCTAssertNil(state.returns["a"])
    }

    func testTheDefaultFormClearsTheOverride() {
        var state = OrbPlacements(overrides: ["a": "bottom"], returns: [:], standard: .top)
        state.set(.notch, for: "a")
        XCTAssertNil(state.overrides["a"])
        XCTAssertEqual(state.placement(for: "a"), .top)
    }

    func testAChosenCornerOrSideIsKept() {
        var state = OrbPlacements(overrides: ["a": "topLeft"], returns: [:], standard: .top)
        state.set(.corner, for: "a")
        XCTAssertEqual(state.placement(for: "a"), .topLeft)
        state.set(.side, for: "a")
        XCTAssertEqual(state.placement(for: "a"), .right)
    }
}
