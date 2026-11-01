import XCTest

@testable import WispCore

final class LyricsTests: XCTestCase {
    private let synced =
        "[00:30.06] The lights go out\n[00:33.90] Tides that I tried\n\n[01:02.5]Second verse\n[00:31.00] "

    func testParsesTimedLinesInOrder() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse(synced: synced, plain: nil))
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.map(\.text), ["The lights go out", "", "Tides that I tried", "Second verse"])
        XCTAssertEqual(lyrics.lines[0].time ?? 0, 30.06, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[3].time ?? 0, 62.5, accuracy: 0.001)
    }

    func testWindowsLineEndings() throws {
        let timed = try XCTUnwrap(Lyrics.parse(synced: "[00:01.00] One\r\n[00:02.00] Two\r\n", plain: nil))
        XCTAssertEqual(timed.lines.map(\.text), ["One", "Two"])
        let plain = try XCTUnwrap(Lyrics.parse(synced: nil, plain: "One\r\nTwo"))
        XCTAssertEqual(plain.lines.map(\.text), ["One", "Two"])
    }

    func testRepeatedLineWithSeveralStamps() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse(synced: "[00:12.00][00:45.00] Chorus\n[00:20.00] Verse", plain: nil))
        XCTAssertEqual(lyrics.lines.map(\.text), ["Chorus", "Verse", "Chorus"])
        XCTAssertEqual(lyrics.lines.map { $0.time ?? -1 }, [12, 20, 45])
    }

    func testCurrentLineFollowsPlayback() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse(synced: synced, plain: nil))
        XCTAssertNil(lyrics.index(at: 10))
        XCTAssertEqual(lyrics.index(at: 30.1), 0)
        XCTAssertEqual(lyrics.index(at: 40), 2)
        XCTAssertEqual(lyrics.index(at: 500), 3)
    }

    func testFallsBackToPlainText() throws {
        let lyrics = try XCTUnwrap(Lyrics.parse(synced: nil, plain: "One\nTwo"))
        XCTAssertFalse(lyrics.isSynced)
        XCTAssertEqual(lyrics.lines.map(\.text), ["One", "Two"])
        XCTAssertNil(lyrics.index(at: 5))
        XCTAssertNil(Lyrics.parse(synced: "", plain: "  "))
    }

    func testDecodesTheServiceResponse() throws {
        let json = #"{"instrumental":false,"plainLyrics":"A","syncedLyrics":"[00:01.00] A"}"#
        let response = try JSONDecoder().decode(LyricsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.lyrics?.lines.first?.text, "A")
        let instrumental = try JSONDecoder().decode(
            LyricsResponse.self, from: Data(#"{"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#.utf8))
        XCTAssertNil(instrumental.lyrics)
    }

    func testQueryURL() throws {
        let url = try XCTUnwrap(LyricsQuery.url(title: "Clocks", artist: "Coldplay", album: "A Rush", duration: 307.4))
        XCTAssertEqual(url.host, "lrclib.net")
        XCTAssertEqual(url.path, "/api/get")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "duration" }?.value, "307")
        XCTAssertEqual(items.first { $0.name == "track_name" }?.value, "Clocks")
        XCTAssertNil(LyricsQuery.url(title: "", artist: "X", album: nil, duration: 0))
    }

    func testOnlyAnswersAndMissesAreCached() {
        XCTAssertTrue(LyricsQuery.isCacheable(status: 200))
        XCTAssertTrue(LyricsQuery.isCacheable(status: 404))
        XCTAssertFalse(LyricsQuery.isCacheable(status: 429))
        XCTAssertFalse(LyricsQuery.isCacheable(status: 500))
        XCTAssertFalse(LyricsQuery.isCacheable(status: 503))
    }
}
