import XCTest

@testable import WispCore

final class NowPlayingParserTests: XCTestCase {
    private let sep = NowPlayingParser.separator

    func testParsesMusicOutput() {
        let raw = ["playing", "Song", "Artist", "Album", "245.5", "61.25"].joined(separator: sep)
        let info = NowPlayingParser.parse(raw, source: .music)
        XCTAssertEqual(info?.title, "Song")
        XCTAssertEqual(info?.artist, "Artist")
        XCTAssertEqual(info?.album, "Album")
        XCTAssertEqual(info?.duration, 245.5)
        XCTAssertEqual(info?.position, 61.25)
        XCTAssertEqual(info?.isPlaying, true)
        XCTAssertEqual(info?.source, .music)
    }

    func testSpotifyDurationIsMilliseconds() {
        let raw = ["paused", "Song", "Artist", "Album", "200000", "12", "https://i.scdn.co/x"].joined(separator: sep)
        let info = NowPlayingParser.parse(raw, source: .spotify)
        XCTAssertEqual(info?.duration, 200)
        XCTAssertEqual(info?.isPlaying, false)
        XCTAssertEqual(info?.artworkURL, URL(string: "https://i.scdn.co/x"))
    }

    func testAcceptsCommaDecimals() {
        let raw = ["playing", "A", "B", "C", "245,5", "1,5"].joined(separator: sep)
        XCTAssertEqual(NowPlayingParser.parse(raw, source: .music)?.duration, 245.5)
    }

    func testStoppedOrMalformedIsNil() {
        XCTAssertNil(NowPlayingParser.parse("stopped", source: .music))
        XCTAssertNil(NowPlayingParser.parse("", source: .music))
        XCTAssertNil(NowPlayingParser.parse(["playing", "only"].joined(separator: sep), source: .music))
    }

    func testProgressClamps() {
        let info = NowPlayingInfo(
            source: .music, title: "t", artist: "a", album: "b", duration: 100, position: 150, isPlaying: true)
        XCTAssertEqual(info.progress, 1)
        XCTAssertEqual(info.remaining, 0)
    }

    func testTrackIdentity() {
        let a = NowPlayingInfo(
            source: .music, title: "t", artist: "a", album: "b", duration: 100, position: 1, isPlaying: true)
        var b = a
        b.position = 50
        XCTAssertEqual(a.trackID, b.trackID)
        b.title = "other"
        XCTAssertNotEqual(a.trackID, b.trackID)
    }
}
