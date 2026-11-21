import Foundation

// MARK: YouTube addresses

/// Reads a YouTube video's ID out of a page address.
public enum YouTubeURL {
    private static let hosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]

    public static func videoID(from address: String) -> String? {
        guard let components = URLComponents(string: address), let host = components.host?.lowercased() else {
            return nil
        }
        let path = components.path.split(separator: "/").map(String.init)
        let candidate: String?
        if host == "youtu.be" {
            candidate = path.first
        } else if hosts.contains(host) {
            if path.first == "watch" {
                candidate = components.queryItems?.first { $0.name == "v" }?.value
            } else if path.count >= 2, ["shorts", "live", "embed"].contains(path[0]) {
                candidate = path[1]
            } else {
                candidate = nil
            }
        } else {
            candidate = nil
        }
        guard let candidate, isID(candidate) else { return nil }
        return candidate
    }

    /// IDs are 11 characters of letters, digits, "-" and "_".
    private static func isID(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

// MARK: Caption tracks

/// One caption track a video offers.
public struct CaptionTrackInfo: Equatable, Sendable {
    public let baseURL: String
    public let language: String
    /// Made by speech recognition rather than a person.
    public let automatic: Bool
}

/// Reads a video's caption tracks from its watch page and turns a track into timed lines.
public enum CaptionTrack {
    private struct Raw: Decodable {
        let baseUrl: String
        let languageCode: String
        let kind: String?
    }

    /// The tracks listed in the page's player response, or none.
    public static func tracks(fromPage html: String) -> [CaptionTrackInfo] {
        guard let start = html.range(of: "\"captionTracks\":")?.upperBound,
            let array = balancedArray(in: html[start...]),
            let raw = try? JSONDecoder().decode([Raw].self, from: Data(array.utf8))
        else { return [] }
        return raw.map { CaptionTrackInfo(baseURL: $0.baseUrl, language: $0.languageCode, automatic: $0.kind == "asr") }
    }

    /// The best track: one in the first of `languages` that has any, then English, then the
    /// first listed; a person's captions before automatic ones in the same language.
    public static func pick(_ tracks: [CaptionTrackInfo], languages: [String]) -> CaptionTrackInfo? {
        func best(_ language: String) -> CaptionTrackInfo? {
            let matching = tracks.filter { $0.language.lowercased().hasPrefix(language.lowercased()) }
            return matching.first { !$0.automatic } ?? matching.first
        }
        for language in languages + ["en"] {
            if let track = best(language) { return track }
        }
        return tracks.first { !$0.automatic } ?? tracks.first
    }

    private struct JSON3: Decodable {
        struct Event: Decodable {
            struct Segment: Decodable { let utf8: String? }
            let tStartMs: Double?
            let segs: [Segment]?
        }
        let events: [Event]?
    }

    /// A track fetched with `fmt=json3`, as timed lines; nil when it has none.
    public static func parse(json3 data: Data) -> Lyrics? {
        guard let decoded = try? JSONDecoder().decode(JSON3.self, from: data), let events = decoded.events else {
            return nil
        }
        let lines = events.compactMap { event -> Lyrics.Line? in
            guard let start = event.tStartMs, let segments = event.segs else { return nil }
            let text = segments.compactMap(\.utf8).joined()
                .replacingOccurrences(of: "\n", with: " ")
                .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            return text.isEmpty ? nil : Lyrics.Line(time: start / 1000, text: text)
        }
        return lines.isEmpty ? nil : Lyrics(lines: lines)
    }

    /// The JSON array starting at the front of `text`, brackets matched outside strings.
    private static func balancedArray(in text: Substring) -> String? {
        guard text.first == "[" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"": inString = true
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { return String(text[text.startIndex...index]) }
            default: break
            }
        }
        return nil
    }
}

// MARK: Which source

/// What fills the lyrics card when a song or video plays.
public enum CaptionSource: Equatable, Sendable {
    case lyrics
    case youTube
    case live
    /// YouTube captions are being fetched.
    case waiting
    /// Live captions are on but miss a permission.
    case needsPermission
    case nothing

    public enum YouTube: Sendable { case off, loading, available, unavailable }
    public enum Live: Sendable { case off, needsPermission, ready }

    public static func choose(hasLyrics: Bool, youTube: YouTube, live: Live) -> CaptionSource {
        if hasLyrics { return .lyrics }
        switch youTube {
        case .available: return .youTube
        case .loading: return .waiting
        case .off, .unavailable: break
        }
        switch live {
        case .ready: return .live
        case .needsPermission: return .needsPermission
        case .off: return .nothing
        }
    }
}

// MARK: Live captions

/// What live captions show: the words heard so far, wrapped into lines, keeping the last few.
public struct LiveCaptionBuffer: Equatable, Sendable {
    public let maxLines: Int
    public let lineLength: Int
    /// Words from segments that have finished.
    private var settled: [String] = []
    private var partial: [String] = []

    public init(maxLines: Int = 3, lineLength: Int = 42) {
        self.maxLines = maxLines
        self.lineLength = lineLength
    }

    /// The current segment's text so far, as the recogniser revises it.
    public mutating func update(partial text: String) {
        partial = text.split(separator: " ").map(String.init)
    }

    /// The current segment ended; its words stay on screen while a new one starts.
    public mutating func finish() {
        settled += partial
        partial = []
        // Only what can still show is kept.
        settled = Array(settled.suffix(maxLines * lineLength))
    }

    public mutating func clear() {
        settled = []
        partial = []
    }

    /// The words wrapped at `lineLength`, the last `maxLines` of them.
    public var lines: [String] {
        var lines: [String] = []
        var current = ""
        for word in settled + partial {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= lineLength {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return Array(lines.suffix(maxLines))
    }

    /// Recognition requests have a time limit, so a segment ends after about 50 seconds, or
    /// at a pause of a second and a half, and a new one starts.
    public static func restarts(segmentAge: TimeInterval, silence: TimeInterval) -> Bool {
        segmentAge >= 50 || silence >= 1.5
    }
}
