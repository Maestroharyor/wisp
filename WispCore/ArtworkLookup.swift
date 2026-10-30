import Foundation

/// Album art from the iTunes Search API, for players that don't hand macOS a picture
/// (browsers often don't). Only the artist and title are sent.
public enum ArtworkQuery {
    public static func url(title: String, artist: String) -> URL? {
        let title = title.trimmingCharacters(in: .whitespaces)
        let artist = artist.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        return components?.url
    }
}

public struct ArtworkSearchResponse: Decodable, Sendable {
    public struct Result: Decodable, Sendable {
        public let artistName: String?
        public let artworkUrl100: String?
    }

    public let results: [Result]

    /// The first result by the same artist, at 600 pt. Nil rather than a guess, so a
    /// near-miss search never shows another song's cover.
    public func artworkURL(artist: String) -> URL? {
        let wanted = artist.lowercased()
        let match = results.first { result in
            guard let name = result.artistName?.lowercased() else { return false }
            return name.contains(wanted) || wanted.contains(name)
        }
        return match?.artworkUrl100
            .map { $0.replacingOccurrences(of: "100x100bb", with: "600x600bb") }
            .flatMap(URL.init(string:))
    }
}
