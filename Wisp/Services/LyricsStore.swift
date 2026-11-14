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
    /// Lookups on their way, so several open lyrics views share one request per song.
    @ObservationIgnored private var inFlight: [String: Task<Lyrics??, Never>] = [:]
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "lyrics")

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
        // Never leave the last song's words up while this one loads or fails.
        lyrics = nil
        guard
            let url = LyricsQuery.url(
                title: info.title, artist: info.artist, album: info.album, duration: info.duration)
        else { return }
        loading = true
        let lookup = inFlight[id] ?? startLookup(url: url, id: id)
        let result = await lookup.value
        // A load for a newer song owns `loading` and `lyrics` now.
        guard trackID == id else { return }
        loading = false
        if let found = result { lyrics = found }
    }

    /// One request for a song, unaffected by the view that started it going away. Nil when it
    /// failed, so a later view can try again; a song with no lyrics is `.some(nil)`.
    private func startLookup(url: URL, id: String) -> Task<Lyrics??, Never> {
        let task = Task { [weak self] () -> Lyrics?? in
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Wisp (https://ayomideodewale.com/wisp)", forHTTPHeaderField: "User-Agent")
            defer { self?.inFlight[id] = nil }
            do {
                // A miss comes back as an error object, which decodes to no lyrics.
                let (data, response) = try await URLSession.shared.data(for: request)
                let found = (try? JSONDecoder().decode(LyricsResponse.self, from: data))?.lyrics
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if LyricsQuery.isCacheable(status: status) { self?.cache[id] = found }
                return .some(found)
            } catch {
                self?.log.debug("lyrics fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        inFlight[id] = task
        return task
    }
}
