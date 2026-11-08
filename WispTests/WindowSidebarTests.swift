import XCTest

@testable import WispCore

final class WindowSidebarTests: XCTestCase {
    // MARK: Destinations

    func testDestinationsRoundTripThroughTheirSavedText() {
        let all: [WindowDestination] = [
            .page(.home), .page(.tray), .page(.media), .widget("calendar"), .widget("agents"),
            .live(.regionWatch), .live(.downloads), .live(.external),
        ]
        for destination in all {
            XCTAssertEqual(WindowDestination(rawValue: destination.rawValue), destination)
        }
        XCTAssertEqual(WindowDestination.widget("notes").rawValue, "widget:notes")
    }

    func testUnknownSavedTextIsNoDestination() {
        XCTAssertNil(WindowDestination(rawValue: ""))
        XCTAssertNil(WindowDestination(rawValue: "page:widgets"))
        XCTAssertNil(WindowDestination(rawValue: "live:meeting"))
        XCTAssertNil(WindowDestination(rawValue: "widget:"))
        XCTAssertNil(WindowDestination(rawValue: "nonsense"))
    }

    // MARK: Sections

    func testTheWispSectionAlwaysHoldsHomeTrayAndMedia() {
        let sections = WindowSidebar.sections(enabledWidgets: [], gridOrder: [], live: [])
        XCTAssertEqual(sections.map(\.kind), [.wisp])
        XCTAssertEqual(sections.first?.rows, [.page(.home), .page(.tray), .page(.media)])
        XCTAssertEqual(sections.first?.title, "Wisp")
    }

    func testWidgetsFollowTheGridOrderWithNewOnesAtTheEnd() {
        let sections = WindowSidebar.sections(
            enabledWidgets: ["calendar", "notes", "timer", "agents"], gridOrder: ["timer", "calendar", "battery"],
            live: [])
        let widgets = sections.first { $0.kind == .widgets }
        XCTAssertEqual(widgets?.title, "Widgets")
        XCTAssertEqual(widgets?.rows, [.widget("timer"), .widget("calendar"), .widget("notes"), .widget("agents")])
    }

    func testLiveRowsShowOnlyWhileRunningInAFixedOrder() {
        let sections = WindowSidebar.sections(
            enabledWidgets: ["notes"], gridOrder: [], live: [.external, .regionWatch, .external])
        XCTAssertEqual(sections.map(\.kind), [.wisp, .widgets, .live])
        XCTAssertEqual(sections.last?.title, "Live")
        XCTAssertEqual(sections.last?.rows, [.live(.regionWatch), .live(.external)])
    }

    func testAVisitingWidgetJoinsTheWidgetsSectionUntilItIsLeft() {
        let sections = WindowSidebar.sections(
            enabledWidgets: ["notes"], gridOrder: [], live: [], visiting: "timer")
        XCTAssertEqual(sections.first { $0.kind == .widgets }?.rows, [.widget("notes"), .widget("timer")])
        // An enabled widget isn't listed twice.
        let enabled = WindowSidebar.sections(enabledWidgets: ["notes"], gridOrder: [], live: [], visiting: "notes")
        XCTAssertEqual(enabled.first { $0.kind == .widgets }?.rows, [.widget("notes")])
        // With nothing enabled, the visitor still gets the section.
        let alone = WindowSidebar.sections(enabledWidgets: [], gridOrder: [], live: [], visiting: "timer")
        XCTAssertEqual(alone.first { $0.kind == .widgets }?.rows, [.widget("timer")])
    }

    // MARK: Fallback

    func testASelectionStillInTheSidebarIsKept() {
        let sections = WindowSidebar.sections(enabledWidgets: ["notes"], gridOrder: [], live: [.downloads])
        XCTAssertEqual(WindowSidebar.resolve(.widget("notes"), in: sections), .widget("notes"))
        XCTAssertEqual(WindowSidebar.resolve(.live(.downloads), in: sections), .live(.downloads))
        XCTAssertEqual(WindowSidebar.resolve(.page(.media), in: sections), .page(.media))
    }

    func testADisabledWidgetOrAnEndedActivityFallsBackToHome() {
        let sections = WindowSidebar.sections(enabledWidgets: ["notes"], gridOrder: [], live: [])
        XCTAssertEqual(WindowSidebar.resolve(.widget("calendar"), in: sections), .page(.home))
        XCTAssertEqual(WindowSidebar.resolve(.live(.regionWatch), in: sections), .page(.home))
        XCTAssertEqual(WindowSidebar.resolve(nil, in: sections), .page(.home))
    }

    // MARK: Shelf pages

    func testShelfPagesMapToTheirRows() {
        XCTAssertEqual(WindowSidebar.destination(forPage: "home", gridWidgets: ["notes"]), .page(.home))
        XCTAssertEqual(WindowSidebar.destination(forPage: "tray", gridWidgets: ["notes"]), .page(.tray))
        XCTAssertEqual(WindowSidebar.destination(forPage: "media", gridWidgets: ["notes"]), .page(.media))
    }

    func testTheWidgetsPageMapsToItsFirstWidgetOrHomeWhenThereIsNone() {
        XCTAssertEqual(
            WindowSidebar.destination(forPage: "widgets", gridWidgets: ["timer", "notes"]), .widget("timer"))
        XCTAssertEqual(WindowSidebar.destination(forPage: "widgets", gridWidgets: []), .page(.home))
        XCTAssertEqual(WindowSidebar.destination(forPage: "elsewhere", gridWidgets: ["timer"]), .page(.home))
    }

    // MARK: Keys

    func testCommandNumbersPickTheWispPagesAndZeroTogglesTheSidebar() {
        XCTAssertEqual(WindowKeys.action(key: "1", commandOnly: true), .select(.home))
        XCTAssertEqual(WindowKeys.action(key: "2", commandOnly: true), .select(.tray))
        XCTAssertEqual(WindowKeys.action(key: "3", commandOnly: true), .select(.media))
        XCTAssertEqual(WindowKeys.action(key: "0", commandOnly: true), .toggleSidebar)
    }

    func testOtherKeysAndOtherModifiersAreLeftAlone() {
        XCTAssertNil(WindowKeys.action(key: "4", commandOnly: true))
        XCTAssertNil(WindowKeys.action(key: "a", commandOnly: true))
        XCTAssertNil(WindowKeys.action(key: "", commandOnly: true))
        XCTAssertNil(WindowKeys.action(key: "12", commandOnly: true))
        // Plain digits type into fields; ⌥⌘1 or ⇧⌘1 belong to someone else.
        XCTAssertNil(WindowKeys.action(key: "1", commandOnly: false))
        XCTAssertNil(WindowKeys.action(key: "0", commandOnly: false))
    }
}

final class ShelfWindowFrameSizeTests: XCTestCase {
    func testTheWindowOpensRoomyAndShrinksNoFurtherThanTheMinimum() {
        XCTAssertEqual(ShelfWindowFrame.defaultSize, CGSize(width: 960, height: 640))
        XCTAssertEqual(ShelfWindowFrame.minimumSize, CGSize(width: 720, height: 480))
    }

    func testASavedFrameFromBeforeIsKeptAndOnlyGrownToTheNewMinimum() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let old = CGRect(x: 100, y: 100, width: 600, height: 420)
        let frame = ShelfWindowFrame.fitted(old, screens: [main], main: main)
        XCTAssertEqual(frame.origin, old.origin)
        XCTAssertEqual(frame.size, ShelfWindowFrame.minimumSize)
        let roomy = CGRect(x: 100, y: 100, width: 800, height: 520)
        XCTAssertEqual(ShelfWindowFrame.fitted(roomy, screens: [main], main: main), roomy)
    }
}
