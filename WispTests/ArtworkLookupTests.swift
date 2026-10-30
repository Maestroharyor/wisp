import XCTest

@testable import WispCore

final class ArtworkLookupTests: XCTestCase {
    func testQueryURLSearchesSongsByArtistAndTitle() throws {
        let url = try XCTUnwrap(ArtworkQuery.url(title: "El Elyon", artist: "Paul Tomisin"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(items.first { $0.name == "term" }?.value, "Paul Tomisin El Elyon")
        XCTAssertEqual(items.first { $0.name == "entity" }?.value, "song")
    }

    func testNoQueryWithoutTitleOrArtist() {
        XCTAssertNil(ArtworkQuery.url(title: "", artist: "Paul Tomisin"))
        XCTAssertNil(ArtworkQuery.url(title: "El Elyon", artist: " "))
    }

    func testPicksTheMatchingArtistAndAsksForALargeImage() throws {
        let json = """
            {"resultCount": 2, "results": [
              {"trackName": "El Elyon", "artistName": "Someone Else",
               "artworkUrl100": "https://example.com/a/100x100bb.jpg"},
              {"trackName": "El Elyon", "artistName": "Paul Tomisin",
               "artworkUrl100": "https://example.com/b/100x100bb.jpg"}
            ]}
            """
        let response = try JSONDecoder().decode(ArtworkSearchResponse.self, from: Data(json.utf8))
        XCTAssertEqual(
            response.artworkURL(artist: "paul tomisin")?.absoluteString, "https://example.com/b/600x600bb.jpg")
    }

    func testNoArtworkWhenNoArtistMatches() throws {
        let json = """
            {"results": [{"artistName": "Someone Else", "artworkUrl100": "https://example.com/a/100x100bb.jpg"}]}
            """
        let response = try JSONDecoder().decode(ArtworkSearchResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.artworkURL(artist: "Paul Tomisin"))
    }
}
