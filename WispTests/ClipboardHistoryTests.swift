import XCTest

@testable import WispCore

final class ClipboardHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 0)

    private func text(_ value: String, _ offset: TimeInterval = 0) -> ClipItem {
        ClipItem(kind: ClipClassifier.kind(for: value), text: value, date: now.addingTimeInterval(offset))
    }

    func testNewestFirstAndDuplicatesMoveToFront() {
        var history = ClipboardHistory()
        history.add(text("one"))
        history.add(text("two", 1))
        history.add(text("one", 2))
        XCTAssertEqual(history.items.map(\.text), ["one", "two"])
    }

    func testDuplicateKeepsPin() {
        var history = ClipboardHistory()
        history.add(text("keep"))
        let id = history.items[0].id
        history.togglePin(id: id)
        history.add(text("keep", 1))
        XCTAssertTrue(history.items[0].pinned)
        XCTAssertEqual(history.items[0].id, id)
    }

    func testImageCopiedAgainFromHistoryMovesToFront() {
        var history = ClipboardHistory(limit: 2)
        history.add(ClipItem(kind: .image, imageFile: "a.png", date: now))
        history.add(text("b", 1))
        var again = history.items[1]
        again.date = now.addingTimeInterval(2)
        let evicted = history.add(again)
        XCTAssertEqual(evicted, [])
        XCTAssertEqual(history.items.map(\.imageFile), ["a.png", nil])
        XCTAssertEqual(Set(history.items.map(\.id)).count, 2)
    }

    func testLimitEvictsOldestUnpinned() {
        var history = ClipboardHistory(limit: 2)
        history.add(text("a"))
        history.togglePin(id: history.items[0].id)
        history.add(text("b", 1))
        let evicted = history.add(text("c", 2))
        XCTAssertEqual(evicted.map(\.text), ["b"])
        XCTAssertEqual(Set(history.items.compactMap(\.text)), ["a", "c"])
    }

    func testFilterByKindAndQueryWithPinnedFirst() {
        var history = ClipboardHistory()
        history.add(text("https://example.com"))
        history.add(text("hello world", 1))
        history.add(text("#FF8800", 2))
        history.togglePin(id: history.items[2].id)
        XCTAssertEqual(history.filtered(kind: .link, query: "").count, 1)
        XCTAssertEqual(history.filtered(kind: nil, query: "WORLD").map(\.text), ["hello world"])
        XCTAssertEqual(history.filtered(kind: nil, query: "").first?.text, "https://example.com")
    }

    func testClearKeepsPinned() {
        var history = ClipboardHistory()
        history.add(text("a"))
        history.add(text("b", 1))
        history.togglePin(id: history.items[1].id)
        history.clearUnpinned()
        XCTAssertEqual(history.items.map(\.text), ["a"])
    }

    func testClassifier() {
        XCTAssertEqual(ClipClassifier.kind(for: "https://apple.com/mac"), .link)
        XCTAssertEqual(ClipClassifier.kind(for: "www.example.org"), .link)
        XCTAssertEqual(ClipClassifier.kind(for: "not a link.com here"), .text)
        XCTAssertEqual(ClipClassifier.kind(for: "#fff"), .color)
        XCTAssertEqual(ClipClassifier.kind(for: "#12345"), .text)
        XCTAssertEqual(ClipClassifier.kind(for: "file:///tmp/x"), .text)
        let rgb = ClipClassifier.rgb(fromHex: "#FF8000")
        XCTAssertEqual(rgb?.red, 255)
        XCTAssertEqual(rgb?.green, 128)
        XCTAssertEqual(rgb?.blue, 0)
    }
}
