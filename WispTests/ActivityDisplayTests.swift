import XCTest

@testable import WispCore

final class ActivityDisplayTests: XCTestCase {
    private let displays = ["builtin", "external"]

    func testPointerFollowsTheDisplayUnderThePointer() {
        let chosen = ActivityDisplayTarget.pointer.displays(
            among: displays, builtIn: "builtin", pointer: "external", main: "builtin")
        XCTAssertEqual(chosen, ["external"])
    }

    func testPointerFallsBackToBuiltInThenMain() {
        XCTAssertEqual(
            ActivityDisplayTarget.pointer.displays(among: displays, builtIn: "builtin", pointer: nil, main: "external"),
            ["builtin"])
        XCTAssertEqual(
            ActivityDisplayTarget.pointer.displays(among: ["a", "b"], builtIn: nil, pointer: "gone", main: "b"),
            ["b"])
    }

    func testBuiltInIgnoresThePointer() {
        let chosen = ActivityDisplayTarget.builtIn.displays(
            among: displays, builtIn: "builtin", pointer: "external", main: "external")
        XCTAssertEqual(chosen, ["builtin"])
    }

    func testBuiltInWithoutALaptopScreenUsesMain() {
        let chosen = ActivityDisplayTarget.builtIn.displays(among: ["a", "b"], builtIn: nil, pointer: "a", main: "b")
        XCTAssertEqual(chosen, ["b"])
    }

    func testAllShowsEverywhere() {
        let chosen = ActivityDisplayTarget.all.displays(
            among: displays, builtIn: "builtin", pointer: "external", main: "builtin")
        XCTAssertEqual(chosen, Set(displays))
    }

    func testNoDisplays() {
        XCTAssertEqual(ActivityDisplayTarget.pointer.displays(among: [], builtIn: nil, pointer: nil, main: nil), [])
    }
}
