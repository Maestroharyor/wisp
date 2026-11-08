import XCTest

@testable import WispCore

final class UpNextTests: XCTestCase {
    private let unit = "\u{1F}"
    private let record = "\u{1E}"

    func testParsesTheNextTracksInThePlaylist() {
        let text = [
            "ok", "Road Trip", ["Dreams", "Fleetwood Mac", "257.8"].joined(separator: unit),
            ["Jolene", "Dolly Parton", "161"].joined(separator: unit),
        ].joined(separator: record)
        XCTAssertEqual(
            UpNext.parse(text),
            .tracks(
                playlist: "Road Trip",
                [
                    UpNextTrack(title: "Dreams", artist: "Fleetwood Mac", duration: 257.8),
                    UpNextTrack(title: "Jolene", artist: "Dolly Parton", duration: 161),
                ]))
    }

    func testTheLastTrackHasNothingNext() {
        XCTAssertEqual(UpNext.parse("ok\u{1E}Road Trip"), .tracks(playlist: "Road Trip", []))
    }

    func testAMissingArtistOrLengthStillShows() {
        XCTAssertEqual(
            UpNext.parse("ok\u{1E}Mix\u{1E}Untitled\u{1F}\u{1F}missing value"),
            .tracks(playlist: "Mix", [UpNextTrack(title: "Untitled", artist: "", duration: nil)]))
    }

    func testShuffleAndRepeatOneHaveNoHonestAnswer() {
        XCTAssertEqual(UpNext.parse("shuffled"), .hidden(.shuffled))
        XCTAssertEqual(UpNext.parse("repeatOne"), .hidden(.repeatingOne))
    }

    func testAnythingElseIsUnavailable() {
        XCTAssertEqual(UpNext.parse(nil), .hidden(.unavailable))
        XCTAssertEqual(UpNext.parse("none"), .hidden(.unavailable))
        XCTAssertEqual(UpNext.parse("execution error"), .hidden(.unavailable))
        XCTAssertEqual(UpNext.parse("ok"), .hidden(.unavailable))
    }

    func testTheScriptNeverLaunchesMusicAndAsksForAFewTracks() {
        let script = UpNext.script(count: 50)
        XCTAssertTrue(script.contains("is not running then return"))
        XCTAssertTrue(script.contains("shuffle enabled"))
        XCTAssertTrue(script.contains("database ID"))
        XCTAssertTrue(script.contains("set wanted to 10"))
        XCTAssertTrue(UpNext.script(count: 0).contains("set wanted to 1"))
    }

    func testOnlyMusicHasAnUpNext() {
        let music = NowPlayingInfo(
            source: .system, title: "a", artist: "b", album: "", duration: 1, position: 0, isPlaying: true,
            appBundleID: "com.apple.Music")
        XCTAssertTrue(UpNext.applies(to: music))
        var spotify = music
        spotify.appBundleID = "com.spotify.client"
        XCTAssertFalse(UpNext.applies(to: spotify))
        let polled = NowPlayingInfo(
            source: .music, title: "a", artist: "b", album: "", duration: 1, position: 0, isPlaying: true)
        XCTAssertTrue(UpNext.applies(to: polled))
        XCTAssertFalse(UpNext.applies(to: nil))
    }
}
