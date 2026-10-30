import Foundation
import OSLog
import Observation
import WispCore

/// Lyrics for the playing song from LRCLIB (free, no account). Only the title, artist,
/// album and length are sent, only while a lyrics view is open, and only when allowed in
/// Settings. Results are cached per track, including "none found".
@MainActor
@Observable
final class LyricsStore {
    private(set) var lyrics: Lyrics?
    private(set) var trackID: String?
    private(set) var loading = false

    @ObservationIgnored private var cache: [String: Lyrics?] = [:]
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let log = Logger(subsystem: "com.maestro.wisp", category: "lyrics")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Fetches lyrics for `info` unless they're cached. Call from a view's `.task(id:)`.
    func load(for info: NowPlayingInfo?) async {
        guard preferences.lyrics, let info else {
            lyrics = nil
            trackID = nil
            return
        }
        let id = info.trackID
        trackID = id
        if let cached = cache[id] {
            lyrics = cached
            return
        }
        guard
            let url = LyricsQuery.url(
                title: info.title, artist: info.artist, album: info.album, duration: info.duration)
        else { return }
        loading = true
        defer { loading = false }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Wisp (https://ayomideodewale.com/wisp)", forHTTPHeaderField: "User-Agent")
        do {
            // A miss comes back as an error object, which decodes to no lyrics.
            let (data, _) = try await URLSession.shared.data(for: request)
            let found = (try? JSONDecoder().decode(LyricsResponse.self, from: data))?.lyrics
            cache[id] = found
            if trackID == id { lyrics = found }
        } catch {
            log.debug("lyrics fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
