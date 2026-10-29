import XCTest

@testable import WispCore

final class MediaBridgeParserTests: XCTestCase {
    func testParsesNowPlayingLine() {
        let line = """
            {"type":"now","title":"Come and see","artist":"RCCG","album":"High Praise","duration":114,"elapsed":38.5,\
            "playing":true,"bundle":"app.zen-browser.zen","app":"Zen","artwork":"aGVsbG8="}
            """
        guard case .nowPlaying(let info, let artwork) = MediaBridgeParser.parse(line) else {
            return XCTFail("expected now playing")
        }
        XCTAssertEqual(info.title, "Come and see")
        XCTAssertEqual(info.artist, "RCCG")
        XCTAssertEqual(info.album, "High Praise")
        XCTAssertEqual(info.duration, 114)
        XCTAssertEqual(info.position, 38.5)
        XCTAssertTrue(info.isPlaying)
        XCTAssertEqual(info.source, .system)
        XCTAssertEqual(info.appBundleID, "app.zen-browser.zen")
        XCTAssertEqual(info.appName, "Zen")
        XCTAssertEqual(artwork, Data("hello".utf8))
    }

    func testMissingOptionalFieldsDefault() {
        let line = #"{"type":"now","title":"Video","playing":false}"#
        guard case .nowPlaying(let info, let artwork) = MediaBridgeParser.parse(line) else {
            return XCTFail("expected now playing")
        }
        XCTAssertEqual(info.artist, "")
        XCTAssertEqual(info.duration, 0)
        XCTAssertFalse(info.isPlaying)
        XCTAssertNil(artwork)
    }

    func testEmptyTitleOrNoneClears() {
        XCTAssertEqual(MediaBridgeParser.parse(#"{"type":"none"}"#), .cleared)
        XCTAssertEqual(MediaBridgeParser.parse(#"{"type":"now","title":""}"#), .cleared)
    }

    func testGarbageIsInvalid() {
        XCTAssertEqual(MediaBridgeParser.parse("not json"), .invalid)
        XCTAssertEqual(MediaBridgeParser.parse(#"{"type":"other"}"#), .invalid)
    }

    func testCommandsSerialise() {
        XCTAssertEqual(MediaBridgeCommand.togglePlayPause.line, "toggle\n")
        XCTAssertEqual(MediaBridgeCommand.next.line, "next\n")
        XCTAssertEqual(MediaBridgeCommand.previous.line, "previous\n")
        XCTAssertEqual(MediaBridgeCommand.seek(42.25).line, "seek 42.25\n")
    }
}
