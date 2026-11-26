import XCTest

@testable import WispCore

final class CommandSearchTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(_ kind: CommandItem.Kind, _ title: String, keywords: String = "") -> CommandItem {
        CommandItem(
            kind: kind, id: "\(kind):\(title)", title: title, subtitle: "", symbol: "circle", keywords: keywords)
    }

    private var candidates: [CommandItem] {
        [
            item(.action, "New note"), item(.action, "Open Settings"),
            item(.page, "Home"), item(.page, "Clipboard"), item(.page, "Calendar"), item(.page, "Notes"),
            item(.page, "Reminders"),
            item(.app, "Calculator"), item(.app, "Notes"),
            item(.clip, "https://example.com/cal"),
            item(.note, "Shopping", keywords: "milk, calendar paper"),
            item(.reminder, "Call the plumber"),
            item(.event, "Calendar review"),
        ]
    }

    func testEmptyQueryListsActionsThenPages() {
        let groups = CommandSearch.results(query: "  ", candidates: candidates, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.kind), [.action, .page])
        XCTAssertEqual(groups[1].items.count, CommandSearch.cap(for: .page))
    }

    func testGroupsComeInAFixedOrderBestMatchFirst() {
        let groups = CommandSearch.results(query: "cal", candidates: candidates, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.kind), [.page, .app, .clip, .note, .reminder, .event])
        XCTAssertEqual(groups[0].items.first?.title, "Calendar")
    }

    func testKeywordsFindAnItemButRankBelowItsTitle() {
        let groups = CommandSearch.results(query: "milk", candidates: candidates, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.kind), [.note])
        let titled = CommandSearch.results(query: "shop", candidates: candidates, now: now, calendar: calendar)
        XCTAssertEqual(titled.first?.items.first?.title, "Shopping")
    }

    func testEachGroupIsCapped() {
        let many = (0..<20).map { item(.clip, "clip \($0)") }
        let groups = CommandSearch.results(query: "clip", candidates: many, now: now, calendar: calendar)
        XCTAssertEqual(groups.first?.items.count, CommandSearch.cap(for: .clip))
    }

    func testAQuickAddSentenceOffersToCreateFirst() {
        let groups = CommandSearch.results(query: "25 min", candidates: candidates, now: now, calendar: calendar)
        XCTAssertEqual(groups.first?.kind, .create)
        XCTAssertEqual(groups.first?.items.first?.title, "25 min timer")
        XCTAssertEqual(groups.first?.items.first?.id, CommandSearch.createID)
    }

    func testAReminderSentenceOffersToCreateIt() {
        let groups = CommandSearch.results(
            query: "remind me to call Sam tomorrow", candidates: [], now: now, calendar: calendar)
        XCTAssertEqual(groups.first?.kind, .create)
        XCTAssertEqual(groups.first?.items.first?.symbol, "checklist")
    }

    func testPlainWordsDontOfferToCreate() {
        let groups = CommandSearch.results(query: "notes", candidates: candidates, now: now, calendar: calendar)
        XCTAssertFalse(groups.contains { $0.kind == .create })
    }

    func testFlatOrderFollowsTheGroups() {
        let groups = CommandSearch.results(query: "cal", candidates: candidates, now: now, calendar: calendar)
        XCTAssertEqual(CommandSearch.flat(groups).first?.title, "Calendar")
        XCTAssertEqual(CommandSearch.flat(groups).count, groups.map(\.items.count).reduce(0, +))
    }

    func testSteppingWrapsAroundTheList() {
        XCTAssertEqual(CommandSearch.stepped(0, by: -1, count: 3), 2)
        XCTAssertEqual(CommandSearch.stepped(2, by: 1, count: 3), 0)
        XCTAssertEqual(CommandSearch.stepped(1, by: 1, count: 3), 2)
        XCTAssertEqual(CommandSearch.stepped(5, by: 1, count: 0), 0)
    }
}
