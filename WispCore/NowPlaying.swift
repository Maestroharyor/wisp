import Foundation

public enum NowPlayingSource: String, Sendable, Equatable, CaseIterable {
    /// System-wide Now Playing (any app, including browsers), via the media bridge.
    case system
    case music
    case spotify

    /// Players polled through AppleScript when the media bridge is unavailable.
    public static let scriptable: [NowPlayingSource] = [.music, .spotify]

    public var bundleID: String {
        switch self {
        case .system: ""
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    public var displayName: String {
        switch self {
        case .system: "Now Playing"
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

public struct NowPlayingInfo: Sendable, Equatable {
    public var source: NowPlayingSource
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds.
    public var duration: Double
    /// Seconds, as of when the info was read.
    public var position: Double
    public var isPlaying: Bool
    public var artworkURL: URL?
    /// The app that owns playback, when known (e.g. a browser's bundle id).
    public var appBundleID: String?
    public var appName: String?

    public init(
        source: NowPlayingSource,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        position: Double,
        isPlaying: Bool,
        artworkURL: URL? = nil,
        appBundleID: String? = nil,
        appName: String? = nil
    ) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
        self.artworkURL = artworkURL
        self.appBundleID = appBundleID ?? (source == .system ? nil : source.bundleID)
        self.appName = appName ?? (source == .system ? nil : source.displayName)
    }

    /// Identifies the track, ignoring playback position, to know when artwork must reload.
    public var trackID: String {
        [source.rawValue, appBundleID ?? "", title, artist, album].joined(separator: "|")
    }

    public var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    public var remaining: Double { max(duration - position, 0) }
}

/// Parses the delimited output of the player AppleScripts.
public enum NowPlayingParser {
    /// Unit separator; never appears in track metadata.
    public static let separator = "\u{1F}"

    /// Fields: state, title, artist, album, duration, position[, artwork URL].
    public static func parse(_ raw: String, source: NowPlayingSource) -> NowPlayingInfo? {
        let fields = raw.components(separatedBy: separator)
        guard fields.count >= 6, let duration = number(fields[4]), let position = number(fields[5]) else {
            return nil
        }
        let state = fields[0].lowercased()
        guard state != "stopped" else { return nil }
        return NowPlayingInfo(
            source: source,
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            // Spotify reports duration in milliseconds.
            duration: source == .spotify ? duration / 1000 : duration,
            position: position,
            isPlaying: state == "playing",
            artworkURL: fields.count > 6 ? URL(string: fields[6]) : nil
        )
    }

    /// AppleScript formats reals with the user's locale, so accept a comma decimal.
    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

/// One update from the media bridge process.
public enum MediaBridgeEvent: Sendable, Equatable {
    case nowPlaying(NowPlayingInfo, artwork: Data?)
    case cleared
    case invalid
}

/// Commands sent to the media bridge on its stdin, one per line.
public enum MediaBridgeCommand: Sendable, Equatable {
    case togglePlayPause
    case next
    case previous
    case seek(Double)

    public var line: String {
        switch self {
        case .togglePlayPause: "toggle\n"
        case .next: "next\n"
        case .previous: "previous\n"
        case .seek(let seconds): "seek \(seconds)\n"
        }
    }
}

/// Parses the JSON lines the media bridge writes to stdout.
public enum MediaBridgeParser {
    private struct Message: Decodable {
        let type: String
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsed: Double?
        let playing: Bool?
        let bundle: String?
        let app: String?
        let artwork: String?
    }

    public static func parse(_ line: String) -> MediaBridgeEvent {
        guard let message = try? JSONDecoder().decode(Message.self, from: Data(line.utf8)) else { return .invalid }
        switch message.type {
        case "none":
            return .cleared
        case "now":
            guard let title = message.title, !title.isEmpty else { return .cleared }
            let info = NowPlayingInfo(
                source: .system,
                title: title,
                artist: message.artist ?? "",
                album: message.album ?? "",
                duration: max(message.duration ?? 0, 0),
                position: max(message.elapsed ?? 0, 0),
                isPlaying: message.playing ?? false,
                appBundleID: message.bundle,
                appName: message.app
            )
            return .nowPlaying(info, artwork: message.artwork.flatMap { Data(base64Encoded: $0) })
        default:
            return .invalid
        }
    }
}
