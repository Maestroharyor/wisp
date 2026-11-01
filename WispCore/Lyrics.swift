import Foundation

/// Song lyrics, timed when the source has timings.
public struct Lyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// Seconds into the song; nil for plain (untimed) lyrics.
        public let time: TimeInterval?
        public let text: String
    }

    public let lines: [Line]
    public var isSynced: Bool { lines.first?.time != nil }

    /// Timed LRC text ("[mm:ss.xx] words") if there is any, otherwise plain text.
    public static func parse(synced: String?, plain: String?) -> Lyrics? {
        if let synced {
            // `\.isNewline` also splits "\r\n", which Swift treats as one Character.
            let lines = synced.split(whereSeparator: \.isNewline).flatMap(timedLines)
                .sorted { ($0.time ?? 0) < ($1.time ?? 0) }
            if !lines.isEmpty { return Lyrics(lines: lines) }
        }
        let text = (plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Lyrics(
            lines: text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map {
                Line(time: nil, text: $0.trimmingCharacters(in: .whitespaces))
            })
    }

    /// The line being sung at `position`, or nil before the first one (or for plain lyrics).
    public func index(at position: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        return lines.lastIndex { ($0.time ?? 0) <= position }
    }

    /// One line per leading stamp: a repeated chorus is written "[00:12.00][00:45.00] words".
    private static func timedLines(_ raw: Substring) -> [Line] {
        var times: [TimeInterval] = []
        var rest = raw
        while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let stamp = rest[rest.index(after: rest.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { break }
            times.append(minutes * 60 + seconds)
            rest = rest[rest.index(after: close)...]
        }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return times.map { Line(time: $0, text: text) }
    }
}

/// The LRCLIB `/api/get` response.
public struct LyricsResponse: Decodable, Sendable {
    public let instrumental: Bool?
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public var lyrics: Lyrics? {
        instrumental == true ? nil : Lyrics.parse(synced: syncedLyrics, plain: plainLyrics)
    }
}

/// Builds the LRCLIB lookup for a song. LRCLIB is free and needs no account.
public enum LyricsQuery {
    /// Whether a response settles the question for this track. Rate limits and server
    /// errors say nothing about the song, so they're retried next time.
    public static func isCacheable(status: Int) -> Bool {
        status == 200 || status == 404
    }

    public static func url(title: String, artist: String, album: String?, duration: TimeInterval) -> URL? {
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if let album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components?.queryItems = items
        return components?.url
    }
}
