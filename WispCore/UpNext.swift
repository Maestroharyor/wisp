import Foundation

/// A track coming up after the one playing.
public struct UpNextTrack: Sendable, Equatable {
    public var title: String
    public var artist: String
    /// Seconds, when Music says.
    public var duration: Double?

    public init(title: String, artist: String, duration: Double?) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// What Music says comes next. Music's AppleScript dictionary has no Up Next queue (and
/// Spotify's has nothing at all), so this is the rest of the playlist that's playing, which
/// is what Music plays next unless you've queued something yourself.
public enum UpNext: Sendable, Equatable {
    case tracks(playlist: String, [UpNextTrack])
    case hidden(Reason)

    public enum Reason: Sendable, Equatable {
        /// Shuffled order isn't exposed, so the playlist order would be wrong.
        case shuffled
        case repeatingOne
        /// Music isn't running, is stopped, or playing something outside a playlist.
        case unavailable
    }

    /// The most tracks shown.
    public static let limit = 10

    /// Up Next is read from Music only, never Spotify or a browser.
    public static func applies(to info: NowPlayingInfo?) -> Bool {
        guard let info else { return false }
        return info.source == .music || info.appBundleID == NowPlayingSource.music.bundleID
    }

    /// Checks the playing track is really at its index in the current playlist, so a track
    /// played from elsewhere never shows the wrong list. Never launches Music.
    public static func script(count: Int) -> String {
        let wanted = min(max(count, 1), limit)
        return """
            if application id "com.apple.Music" is not running then return "none"
            tell application id "com.apple.Music"
                try
                    if player state is stopped then return "none"
                    if shuffle enabled then return "shuffled"
                    if song repeat is one then return "repeatOne"
                    set p to current playlist
                    set t to current track
                    set i to index of t
                    set n to count of tracks of p
                    if i < 1 or i > n then return "none"
                    if database ID of track i of p is not database ID of t then return "none"
                    set d to character id 31
                    set r to character id 30
                    set out to "ok" & r & (name of p as text)
                    set wanted to \(wanted)
                    set k to i
                    repeat wanted times
                        set k to k + 1
                        if k > n then
                            if song repeat is all then
                                set k to 1
                            else
                                exit repeat
                            end if
                        end if
                        if k = i then exit repeat
                        set x to track k of p
                        set out to out & r & (name of x as text) & d & (artist of x as text) & d & (duration of x as text)
                    end repeat
                    return out
                on error
                    return "none"
                end try
            end tell
            """
    }

    /// Reads `script(count:)`'s output: records split by U+001E, fields by U+001F.
    public static func parse(_ text: String?) -> UpNext {
        guard let text else { return .hidden(.unavailable) }
        switch text {
        case "shuffled": return .hidden(.shuffled)
        case "repeatOne": return .hidden(.repeatingOne)
        default: break
        }
        let records = text.split(separator: "\u{1E}", omittingEmptySubsequences: false).map(String.init)
        guard records.count >= 2, records[0] == "ok" else { return .hidden(.unavailable) }
        let tracks = records.dropFirst(2).compactMap { record -> UpNextTrack? in
            let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            let title = value(fields.first)
            guard !title.isEmpty else { return nil }
            let seconds = Double(value(fields.count > 2 ? fields[2] : nil).replacingOccurrences(of: ",", with: "."))
            return UpNextTrack(title: title, artist: value(fields.count > 1 ? fields[1] : nil), duration: seconds)
        }
        return .tracks(playlist: value(records[1]), tracks)
    }

    /// AppleScript writes a missing field as "missing value".
    private static func value(_ field: String?) -> String {
        guard let field, field != "missing value" else { return "" }
        return field.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
