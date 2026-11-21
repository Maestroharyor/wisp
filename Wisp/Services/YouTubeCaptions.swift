import AppKit
import Foundation
import OSLog
import WispCore

/// The address of a browser's front tab, read through Automation. Only Safari and Chromium
/// browsers answer; Firefox and Zen have no scripting for it. The address is used for its video
/// ID and never logged.
@MainActor
enum BrowserTab {
    /// Browsers that answer, and the property that holds the front tab.
    private static let scripts: [String: String] = [
        "com.apple.Safari": "URL of current tab of front window",
        "com.apple.SafariTechnologyPreview": "URL of current tab of front window",
        "com.google.Chrome": "URL of active tab of front window",
        "com.google.Chrome.beta": "URL of active tab of front window",
        "company.thebrowser.Browser": "URL of active tab of front window",
        "com.brave.Browser": "URL of active tab of front window",
        "com.microsoft.edgemac": "URL of active tab of front window",
        "com.vivaldi.Vivaldi": "URL of active tab of front window",
        "com.operasoftware.Opera": "URL of active tab of front window",
    ]

    static func supports(_ bundleID: String) -> Bool { scripts[bundleID] != nil }

    /// The front tab's address, or nil when the browser won't say (or Automation is refused).
    static func address(of bundleID: String) -> String? {
        guard let property = scripts[bundleID] else { return nil }
        let source = "tell application id \"\(bundleID)\" to get \(property)"
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }
}

/// A YouTube video's own captions, fetched once per video while it plays in a browser that
/// can share its tab. Sends only the video ID, without cookies.
@MainActor
@Observable
final class YouTubeCaptions {
    private(set) var state: CaptionSource.YouTube = .off
    private(set) var captions: Lyrics?

    @ObservationIgnored private var cache: [String: Lyrics?] = [:]
    @ObservationIgnored private var current: String?
    private static let session = URLSession(configuration: .ephemeral)
    private static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "YouTubeCaptions")

    /// Looks up captions for what's playing: a YouTube video in a browser that answers.
    func load(for info: NowPlayingInfo?, enabled: Bool) async {
        guard enabled, let info, let browser = info.appBundleID, BrowserTab.supports(browser) else {
            state = enabled ? .unavailable : .off
            captions = nil
            current = nil
            return
        }
        guard let address = BrowserTab.address(of: browser), let id = YouTubeURL.videoID(from: address) else {
            state = .unavailable
            captions = nil
            return
        }
        current = id
        if let cached = cache[id] {
            captions = cached
            state = cached == nil ? .unavailable : .available
            return
        }
        state = .loading
        let found = await Self.fetch(id)
        // A newer video started meanwhile.
        guard current == id else { return }
        cache[id] = found
        captions = found
        state = found == nil ? .unavailable : .available
    }

    private static func fetch(_ id: String) async -> Lyrics? {
        guard let page = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return nil }
        var request = URLRequest(url: page)
        // Without a language the page can list tracks for another region first.
        request.setValue(Locale.preferredLanguages.first ?? "en", forHTTPHeaderField: "Accept-Language")
        do {
            let (data, _) = try await session.data(for: request)
            let tracks = CaptionTrack.tracks(fromPage: String(decoding: data, as: UTF8.self))
            let languages = Locale.preferredLanguages.map { String($0.prefix(2)) }
            guard let track = CaptionTrack.pick(tracks, languages: languages),
                let url = URL(string: track.baseURL + "&fmt=json3")
            else { return nil }
            let (json, _) = try await session.data(from: url)
            return CaptionTrack.parse(json3: json)
        } catch {
            log.notice("couldn't fetch captions: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
