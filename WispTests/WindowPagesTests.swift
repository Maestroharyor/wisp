import XCTest

@testable import WispCore

final class WindowPagesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    // MARK: Week grid

    func testEventsThatDontOverlapShareOneLane() {
        let placed = WeekGrid.lanes([date(21, 9)...date(21, 10), date(21, 10)...date(21, 11)])
        XCTAssertEqual(placed.map(\.lane), [0, 0])
        XCTAssertEqual(placed.map(\.lanes), [1, 1])
    }

    func testOverlappingEventsSitSideBySide() {
        let placed = WeekGrid.lanes([
            date(21, 9)...date(21, 11), date(21, 10)...date(21, 12), date(21, 13)...date(21, 14),
        ])
        XCTAssertEqual(placed.map(\.lane), [0, 1, 0])
        XCTAssertEqual(placed.map(\.lanes), [2, 2, 1])
    }

    func testAThirdOverlapReusesAFreedLane() {
        let placed = WeekGrid.lanes([
            date(21, 9)...date(21, 10), date(21, 9, 30)...date(21, 11), date(21, 10)...date(21, 10, 30),
        ])
        XCTAssertEqual(placed.map(\.lane), [0, 1, 0])
        XCTAssertEqual(placed.map(\.lanes), [2, 2, 2])
    }

    func testTheHourRangeCoversWorkingHoursAndEveryEvent() {
        XCTAssertEqual(WeekGrid.hours(events: [], working: 9...17, calendar: calendar), 8...18)
        XCTAssertEqual(
            WeekGrid.hours(events: [date(21, 6, 30)...date(21, 7, 15)], working: 9...17, calendar: calendar), 6...18)
        XCTAssertEqual(
            WeekGrid.hours(events: [date(21, 20)...date(21, 23, 30)], working: 9...17, calendar: calendar), 8...24)
    }

    func testAnEventsPlaceInTheGrid() {
        let frame = WeekGrid.frame(
            for: date(21, 9, 30)...date(21, 11), dayStart: date(21, 0), hours: 8...18, hourHeight: 60)
        XCTAssertEqual(frame.top, 90, accuracy: 0.01)
        XCTAssertEqual(frame.height, 90, accuracy: 0.01)
    }

    func testAShortEventStillHasRoomForItsTitle() {
        let frame = WeekGrid.frame(
            for: date(21, 9)...date(21, 9, 5), dayStart: date(21, 0), hours: 8...18, hourHeight: 60)
        XCTAssertEqual(frame.height, WeekGrid.minimumHeight)
    }

    func testCalendarLayoutsReadBackFromTheirNames() {
        XCTAssertEqual(CalendarLayout.allCases.map(\.title), ["Day", "Week", "Agenda"])
        XCTAssertEqual(CalendarLayout(rawValue: "week"), .week)
    }

    // MARK: Notes

    func testANotesTitleAndPreviewComeFromItsLines() {
        let note = Note(body: "\n  Trip plan  \nBook flights\nPack", updated: date(21, 9))
        XCTAssertEqual(note.title, "Trip plan")
        XCTAssertEqual(note.preview, "Book flights")
        XCTAssertEqual(Note(body: "  \n", updated: date(21, 9)).title, "New note")
        XCTAssertTrue(Note(body: "  \n", updated: date(21, 9)).isEmpty)
        XCTAssertEqual(Note(body: String(repeating: "a", count: 90), updated: .now).title.count, 60)
    }

    func testPinnedNotesComeFirstThenTheNewest() {
        var book = NoteBook()
        let old = book.add(body: "Old", at: date(20, 9))
        let new = book.add(body: "New", at: date(21, 9))
        let pinned = book.add(body: "Pinned", at: date(19, 9))
        book.togglePin(pinned)
        XCTAssertEqual(book.sorted.map(\.id), [pinned, new, old])
    }

    func testEditingANoteMovesItUp() {
        var book = NoteBook()
        let first = book.add(body: "First", at: date(20, 9))
        let second = book.add(body: "Second", at: date(21, 9))
        book.update(first, body: "First, edited", at: date(21, 10))
        XCTAssertEqual(book.sorted.map(\.id), [first, second])
        XCTAssertEqual(book.note(first)?.body, "First, edited")
    }

    func testSearchIgnoresCaseAndAccents() {
        var book = NoteBook()
        let cafe = book.add(body: "Café list", at: date(21, 9))
        _ = book.add(body: "Groceries", at: date(21, 8))
        XCTAssertEqual(book.search("CAFE").map(\.id), [cafe])
        XCTAssertEqual(book.search(" ").count, 2)
    }

    func testRemovingANote() {
        var book = NoteBook()
        let note = book.add(body: "Gone", at: date(21, 9))
        book.remove(note)
        XCTAssertTrue(book.notes.isEmpty)
    }

    func testTheOldSingleNoteBecomesTheFirstNote() {
        XCTAssertEqual(NoteBook.migrated(fromSingle: "Hello", at: date(21, 9)).notes.map(\.body), ["Hello"])
        XCTAssertTrue(NoteBook.migrated(fromSingle: " \n", at: date(21, 9)).notes.isEmpty)
    }

    func testNotesSurviveSaving() throws {
        var book = NoteBook()
        let id = book.add(body: "Keep me", at: date(21, 9))
        book.togglePin(id)
        let read = try JSONDecoder().decode(NoteBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(read, book)
    }

    // MARK: Reminders

    func testReminderFiltersAndTheirCounts() {
        let now = date(21, 12)
        let items = [
            ReminderItem(id: "a", title: "Late", due: date(20, 9), isCompleted: false),
            ReminderItem(id: "b", title: "Today", due: date(21, 17), isCompleted: false),
            ReminderItem(id: "c", title: "Later", due: date(25, 9), isCompleted: false),
            ReminderItem(id: "d", title: "Someday", due: nil, isCompleted: false),
        ]
        func ids(_ filter: ReminderFilter) -> [String] {
            filter.apply(items, now: now, calendar: calendar).map(\.id)
        }
        XCTAssertEqual(ids(.all), ["a", "b", "c", "d"])
        XCTAssertEqual(ids(.today), ["b"])
        XCTAssertEqual(ids(.overdue), ["a"])
        XCTAssertEqual(ids(.scheduled), ["a", "b", "c"])
        XCTAssertEqual(ReminderFilter.overdue.count(items, now: now, calendar: calendar), 1)
    }

    func testRemindersGroupByList() {
        let items = [
            ReminderItem(id: "a", title: "A", due: nil, isCompleted: false, list: "Work"),
            ReminderItem(id: "b", title: "B", due: nil, isCompleted: false, list: "Home"),
            ReminderItem(id: "c", title: "C", due: nil, isCompleted: false, list: "Work"),
            ReminderItem(id: "d", title: "D", due: nil, isCompleted: false),
        ]
        let lists = ReminderListSummary.summaries(items)
        XCTAssertEqual(lists.map(\.name), ["Work", "Home"])
        XCTAssertEqual(lists.map(\.count), [2, 1])
    }

    // MARK: Clipboard

    func testClipCountsByKind() {
        let items = [
            ClipItem(kind: .text, text: "a", date: .now),
            ClipItem(kind: .text, text: "b", date: .now),
            ClipItem(kind: .link, text: "https://x", date: .now),
        ]
        let counts = ClipCounts(items)
        XCTAssertEqual(counts.all, 3)
        XCTAssertEqual(counts[.text], 2)
        XCTAssertEqual(counts[.image], 0)
    }

    func testClipsCountByApp() {
        let items = [
            ClipItem(kind: .text, text: "a", sourceApp: "Safari", sourceBundleID: "com.apple.Safari", date: .now),
            ClipItem(kind: .text, text: "b", sourceApp: "Notes", date: .now),
            ClipItem(kind: .text, text: "c", sourceApp: "Safari", date: .now),
            ClipItem(kind: .text, text: "d", date: .now),
        ]
        let apps = ClipCounts.apps(items)
        XCTAssertEqual(apps.map(\.name), ["Safari", "Notes"])
        XCTAssertEqual(apps.first?.count, 2)
        XCTAssertEqual(apps.first?.bundleID, "com.apple.Safari")
    }

    func testCodeLooksLikeCode() {
        XCTAssertTrue(ClipLook.isCode("function debounce(fn, ms) {\n  let t;\n  return () => {}\n}"))
        XCTAssertTrue(ClipLook.isCode("const f = (x) => x * 2"))
        XCTAssertFalse(ClipLook.isCode("Looking forward to the sync tomorrow at 10."))
        XCTAssertFalse(ClipLook.isCode("Milk\nEggs\nCoffee beans"))
    }

    // MARK: Layout

    func testAListAndItsDetailSitSideBySideWhenThereIsRoom() {
        XCTAssertFalse(WindowLayout.masterDetail(width: 700))
        XCTAssertTrue(WindowLayout.masterDetail(width: 760))
    }
}
