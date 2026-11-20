import XCTest

@testable import WispCore

final class AppWindowsTests: XCTestCase {
    private func window(_ title: String?, minimised: Bool = false) -> WindowSummary {
        WindowSummary(title: title, isMinimised: minimised)
    }

    func testWindowsKeepTheirTitlesAndUntitledOnesAreNumbered() {
        let choices = AppWindows.choices(appName: "Safari", windows: [window("GitHub"), window(nil), window("  ")])
        XCTAssertEqual(choices.map(\.title), ["GitHub", "Safari window 2", "Safari window 3"])
    }

    func testMinimisedWindowsSaySo() {
        let choices = AppWindows.choices(appName: "Notes", windows: [window("A"), window("B", minimised: true)])
        XCTAssertEqual(choices.last?.title, "B (minimised)")
        XCTAssertEqual(choices.last?.icon, .symbol(AppWindows.minimisedSymbol))
        XCTAssertEqual(choices.first?.icon, .symbol(AppWindows.windowSymbol))
    }

    func testOneWindowNeedsNoSubRing() {
        XCTAssertTrue(AppWindows.choices(appName: "Notes", windows: [window("A")]).isEmpty)
        XCTAssertTrue(AppWindows.choices(appName: "Notes", windows: []).isEmpty)
    }

    func testManyWindowsEndWithACountOfTheRest() {
        let windows = (1...9).map { window("W\($0)") }
        let choices = AppWindows.choices(appName: "Finder", windows: windows)
        XCTAssertEqual(choices.count, AppWindows.limit)
        XCTAssertEqual(choices.last?.title, "4 more")
        XCTAssertNil(choices.last.flatMap(AppWindows.target(of:)))
    }

    func testChoicesPointBackAtTheirWindow() {
        let choices = AppWindows.choices(appName: "Safari", windows: [window("A"), window("B")])
        XCTAssertEqual(choices.last.flatMap(AppWindows.target(of:)), AppWindows.Target(index: 1, title: "B"))
        XCTAssertNil(AppWindows.target(of: RingChoice(id: "form:orb", title: "Orb", symbol: "circle")))
    }

    func testATargetFindsItsWindowEvenAfterTheOrderChanged() {
        let now = [window("B"), window("A"), window("C")]
        XCTAssertEqual(AppWindows.match(AppWindows.Target(index: 0, title: "A"), in: now), 1)
        XCTAssertNil(AppWindows.match(AppWindows.Target(index: 2, title: "Gone"), in: now))
        XCTAssertEqual(AppWindows.match(AppWindows.Target(index: 1, title: nil), in: [window(nil), window(nil)]), 1)
        XCTAssertNil(AppWindows.match(AppWindows.Target(index: 1, title: nil), in: [window(nil), window("Titled")]))
    }
}
