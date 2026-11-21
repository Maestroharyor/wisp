import XCTest

@testable import WispCore

final class CaptionsTests: XCTestCase {
    // MARK: YouTube addresses

    func testVideoIDsFromEveryKindOfAddress() {
        XCTAssertEqual(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeURL.videoID(from: "https://youtu.be/dQw4w9WgXcQ?si=abc"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeURL.videoID(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeURL.videoID(from: "https://www.youtube.com/live/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeURL.videoID(from: "https://music.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertNil(YouTubeURL.videoID(from: "https://www.youtube.com/feed/subscriptions"))
        XCTAssertNil(YouTubeURL.videoID(from: "https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=bad"))
    }

    // MARK: Caption tracks

    private let page = #"""
        <script>var ytInitialPlayerResponse = {"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=en&kind=asr","name":{"simpleText":"English (auto-generated)"},"languageCode":"en","kind":"asr"},{"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=en","name":{"simpleText":"English [x]"},"languageCode":"en"},{"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=fr","name":{"simpleText":"French"},"languageCode":"fr"}]}}};</script>
        """#

    func testTracksAreReadFromTheWatchPage() {
        let tracks = CaptionTrack.tracks(fromPage: page)
        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(tracks.first?.baseURL, "https://www.youtube.com/api/timedtext?v=abc&lang=en&kind=asr")
        XCTAssertEqual(tracks.first?.automatic, true)
        XCTAssertTrue(CaptionTrack.tracks(fromPage: "<html>no captions</html>").isEmpty)
    }

    func testAPersonsCaptionsInYourLanguageWin() {
        let tracks = CaptionTrack.tracks(fromPage: page)
        XCTAssertEqual(CaptionTrack.pick(tracks, languages: ["fr"])?.language, "fr")
        let english = CaptionTrack.pick(tracks, languages: ["de"])
        XCTAssertEqual(english?.language, "en")
        XCTAssertEqual(english?.automatic, false)
    }

    func testJSONCaptionsBecomeTimedLines() throws {
        let json = #"""
            {"events":[
              {"tStartMs":0,"dDurationMs":1500,"segs":[{"utf8":"Hello "},{"utf8":"there"}]},
              {"tStartMs":1500,"dDurationMs":100,"segs":[{"utf8":"\n"}]},
              {"tStartMs":2000,"dDurationMs":2000,"segs":[{"utf8":"second\nline"}]},
              {"tStartMs":5000}
            ]}
            """#
        let lyrics = try XCTUnwrap(CaptionTrack.parse(json3: Data(json.utf8)))
        XCTAssertEqual(lyrics.lines.map(\.text), ["Hello there", "second line"])
        XCTAssertEqual(lyrics.lines.map(\.time), [0, 2])
        XCTAssertNil(CaptionTrack.parse(json3: Data("{}".utf8)))
    }

    // MARK: Which source

    func testLyricsComeFirstThenYouTubeThenLive() {
        XCTAssertEqual(
            CaptionSource.choose(hasLyrics: true, youTube: .available, live: .ready), .lyrics)
        XCTAssertEqual(
            CaptionSource.choose(hasLyrics: false, youTube: .available, live: .ready), .youTube)
        XCTAssertEqual(
            CaptionSource.choose(hasLyrics: false, youTube: .unavailable, live: .ready), .live)
        XCTAssertEqual(
            CaptionSource.choose(hasLyrics: false, youTube: .loading, live: .ready), .waiting)
        XCTAssertEqual(
            CaptionSource.choose(hasLyrics: false, youTube: .off, live: .needsPermission), .needsPermission)
        XCTAssertEqual(
            CaptionSource.choose(hasLyrics: false, youTube: .off, live: .off), .nothing)
    }

    // MARK: Live captions

    func testLiveCaptionsKeepTheLastThreeLines() {
        var buffer = LiveCaptionBuffer(maxLines: 3, lineLength: 20)
        buffer.update(partial: "the quick brown fox jumps over the lazy dog")
        XCTAssertEqual(buffer.lines, ["the quick brown fox", "jumps over the lazy", "dog"])
        buffer.finish()
        buffer.update(partial: "and then it ran away into the woods far away")
        XCTAssertEqual(buffer.lines, ["dog and then it ran", "away into the woods", "far away"])
    }

    func testASegmentRestartsAfterALongRunOrASilence() {
        XCTAssertFalse(LiveCaptionBuffer.restarts(segmentAge: 20, silence: 0.5))
        XCTAssertTrue(LiveCaptionBuffer.restarts(segmentAge: 51, silence: 0))
        XCTAssertTrue(LiveCaptionBuffer.restarts(segmentAge: 10, silence: 1.6))
    }
}
