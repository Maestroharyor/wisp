import XCTest

@testable import WispCore

final class NotificationTests: XCTestCase {
    /// Mirrors the usernoted record plist: top-level app/date plus a request dictionary.
    private struct FixtureRecord: Encodable {
        struct Request: Encodable {
            var titl: String?
            var subt: String?
            var body: String?
            var thre: String?
        }
        var app: String
        var date: Double?
        var req: Request
    }

    private func plist(_ record: FixtureRecord) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(record)
    }

    private func record(_ id: Int64, app: String = "com.apple.MobileSMS", title: String = "Ada", uuid: String? = nil)
        -> NotificationRecord
    {
        NotificationRecord(
            recID: id, appID: app, title: title, subtitle: "", body: "Hi", threadID: nil,
            date: Date(timeIntervalSinceReferenceDate: 0), uuid: uuid ?? "u\(id)")
    }

    // MARK: Decoding

    func testDecodesRecordPlist() throws {
        let data = try plist(
            FixtureRecord(
                app: "com.apple.MobileSMS", date: 750_000_000,
                req: .init(titl: "Ada Lovelace", subt: "Group", body: "Lunch?", thre: "chat-1")))
        let decoded = NotificationRecord.decode(
            recID: 7, appIdentifier: "com.apple.MobileSMS", data: data, deliveredDate: 750_000_001, uuid: "abc")
        XCTAssertEqual(decoded?.recID, 7)
        XCTAssertEqual(decoded?.title, "Ada Lovelace")
        XCTAssertEqual(decoded?.subtitle, "Group")
        XCTAssertEqual(decoded?.body, "Lunch?")
        XCTAssertEqual(decoded?.threadID, "chat-1")
        XCTAssertEqual(decoded?.appID, "com.apple.MobileSMS")
        XCTAssertEqual(decoded?.date, Date(timeIntervalSinceReferenceDate: 750_000_001))
        XCTAssertEqual(decoded?.uuid, "abc")
    }

    func testDecodeRejectsEmptyOrGarbage() throws {
        let empty = try plist(FixtureRecord(app: "x", date: nil, req: .init()))
        XCTAssertNil(NotificationRecord.decode(recID: 1, appIdentifier: "x", data: empty, deliveredDate: 0, uuid: nil))
        XCTAssertNil(
            NotificationRecord.decode(
                recID: 1, appIdentifier: "x", data: Data("nope".utf8), deliveredDate: 0, uuid: nil)
        )
    }

    func testBodyOnlyNotificationUsesAppNameLater() throws {
        let data = try plist(FixtureRecord(app: "x", date: nil, req: .init(body: "Build finished")))
        let decoded = NotificationRecord.decode(recID: 1, appIdentifier: "x", data: data, deliveredDate: 0, uuid: nil)
        XCTAssertEqual(decoded?.title, "")
        XCTAssertEqual(decoded?.body, "Build finished")
    }

    // MARK: Feed

    func testFirstIngestLocksBaselineSilently() {
        var feed = NotificationFeed(ownBundleID: "com.ayomideodewale.wisp")
        XCTAssertNil(feed.cursor)
        XCTAssertEqual(feed.ingest([record(1), record(5)], baseline: 5), [])
        XCTAssertEqual(feed.cursor, 5)
    }

    func testOnlyNewerRecordsPassAndCursorAdvances() {
        var feed = NotificationFeed(ownBundleID: "com.ayomideodewale.wisp")
        _ = feed.ingest([], baseline: 5)
        let shown = feed.ingest([record(4), record(6), record(7)], baseline: nil)
        XCTAssertEqual(shown.map(\.recID), [6, 7])
        XCTAssertEqual(feed.cursor, 7)
        XCTAssertEqual(feed.ingest([record(7)], baseline: nil), [])
    }

    func testFloodKeepsNewest() {
        var feed = NotificationFeed(ownBundleID: "com.ayomideodewale.wisp", maxPerPoll: 2)
        _ = feed.ingest([], baseline: 0)
        let shown = feed.ingest((1...5).map { record($0) }, baseline: nil)
        XCTAssertEqual(shown.map(\.recID), [4, 5])
        XCTAssertEqual(feed.cursor, 5)
    }

    func testBlockedOwnAndDuplicateUUIDsAreDropped() {
        var feed = NotificationFeed(ownBundleID: "com.ayomideodewale.wisp", blockedApps: ["com.spam"])
        _ = feed.ingest([], baseline: 0)
        let shown = feed.ingest(
            [
                record(1, app: "com.spam"), record(2, app: "com.ayomideodewale.wisp"), record(3, uuid: "same"),
                record(4, uuid: "same"),
            ], baseline: nil)
        XCTAssertEqual(shown.map(\.recID), [3])
    }

    // MARK: Replies

    func testReplyRouting() {
        XCTAssertEqual(ReplyRouting.channel(for: "com.apple.MobileSMS"), .iMessage)
        XCTAssertEqual(ReplyRouting.channel(for: "net.whatsapp.WhatsApp"), .whatsApp)
        XCTAssertEqual(ReplyRouting.channel(for: "ru.keepcoder.Telegram"), .telegram)
        XCTAssertEqual(ReplyRouting.channel(for: "com.apple.mail"), nil)
    }

    func testAppleScriptEscaping() {
        XCTAssertEqual(AppleScriptText.quoted(#"He said "hi" \o/"#), #""He said \"hi\" \\o/""#)
    }

    func testChatMatcherPrefersMatchingTextThenName() {
        let chats = [
            ChatCandidate(guid: "iMessage;-;+1555", lastIncomingText: "See you", displayName: nil, handle: "+1555"),
            ChatCandidate(guid: "iMessage;-;ada@x", lastIncomingText: "Lunch?", displayName: nil, handle: "ada@x"),
            ChatCandidate(guid: "iMessage;+;group", lastIncomingText: "ok", displayName: "Team", handle: nil),
        ]
        XCTAssertEqual(ChatMatcher.pick(chats, title: "Ada", body: "Lunch?"), "iMessage;-;ada@x")
        XCTAssertEqual(ChatMatcher.pick(chats, title: "Team", body: "different"), "iMessage;+;group")
        XCTAssertEqual(ChatMatcher.pick(chats, title: "+1555", body: "x"), "iMessage;-;+1555")
        XCTAssertNil(ChatMatcher.pick(chats, title: "Nobody", body: "nothing"))
    }

    // MARK: Focus

    func testFocusAssertionsParse() {
        let active = #"""
            {"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}
            """#
        let modes = #"""
            {"data":[{"modeConfigurations":{"com.apple.focus.work":{"mode":{"name":"Work","symbolImageName":"briefcase.fill"}}}}]}
            """#
        let state = FocusModeState.parse(assertions: Data(active.utf8), modes: Data(modes.utf8))
        XCTAssertEqual(state, FocusModeState(isOn: true, name: "Work", symbol: "briefcase.fill"))

        let off = #"{"data":[{"storeAssertionRecords":[]}]}"#
        XCTAssertEqual(
            FocusModeState.parse(assertions: Data(off.utf8), modes: nil),
            FocusModeState(isOn: false, name: nil, symbol: nil))
        XCTAssertNil(FocusModeState.parse(assertions: Data("x".utf8), modes: nil))
    }

    func testDefaultFocusNameWhenModesMissing() {
        let active = #"""
            {"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}
            """#
        let state = FocusModeState.parse(assertions: Data(active.utf8), modes: nil)
        XCTAssertEqual(state?.name, "Do Not Disturb")
        XCTAssertEqual(state?.symbol, "moon.fill")
    }

    // MARK: Sizing

    func testNotificationSurfaces() {
        let layout = NotchGeometry.layout(
            for: ScreenMetrics(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                safeAreaTop: 32,
                auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
                auxiliaryTopRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
            ))
        let card = SurfaceSizing.rect(for: .notification(replying: false), in: layout)
        let reply = SurfaceSizing.rect(for: .notification(replying: true), in: layout)
        XCTAssertEqual(card.width, SurfaceSizing.notificationWidth)
        XCTAssertEqual(card.height, 32 + SurfaceSizing.notificationCardHeight)
        XCTAssertEqual(reply.height - card.height, SurfaceSizing.replyBarHeight)
    }
}
