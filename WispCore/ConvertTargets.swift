import CoreGraphics
import Foundation

/// A format the ring's Transform segment can convert dropped files to.
public enum ConvertFormat: String, CaseIterable, Sendable {
    case jpeg, png, heic, tiff, gif, mp4, mov, m4a, wav, aiff

    /// The extension written, which is also how the format is named on the ring.
    public var ext: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        default: rawValue
        }
    }

    public var title: String { ext.uppercased() }

    public var symbol: String {
        switch self {
        case .jpeg, .png, .heic, .tiff: "photo"
        case .gif: "photo.stack"
        case .mp4, .mov: "film"
        case .m4a, .wav, .aiff: "waveform"
        }
    }
}

/// Which formats to offer for the files being dragged, as the numbered sub-ring around
/// Transform: only what every file can become, without the format they're all in already.
public enum ConvertTargets {
    public enum Kind: Equatable, Sendable { case image, video, audio, other }

    private static let prefix = "convert:"
    /// The panel, for anything the quick formats don't cover.
    public static let moreID = "convert:more"

    public static func formats(for kind: Kind) -> [ConvertFormat] {
        switch kind {
        case .image: [.jpeg, .png, .heic, .tiff, .gif]
        case .video: [.mp4, .mov, .gif, .m4a]
        case .audio: [.m4a, .wav, .aiff]
        case .other: []
        }
    }

    /// The kind of file, from its extension; what the drag pasteboard offers without opening it.
    public static func kind(ofExtension ext: String) -> Kind {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp": .image
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": .video
        case "m4a", "mp3", "wav", "aif", "aiff", "caf", "flac", "aac": .audio
        default: .other
        }
    }

    /// As `formats(forExtensions:)`, leaving out M4A when a dragged video is known to have no
    /// sound. Nil means it isn't known (the check was slow), so M4A stays.
    public static func formats(forExtensions exts: [String], videosHaveSound: Bool?) -> [ConvertFormat] {
        let formats = formats(forExtensions: exts)
        guard videosHaveSound == false, exts.contains(where: { kind(ofExtension: $0) == .video }) else {
            return formats
        }
        return formats.filter { $0 != .m4a }
    }

    /// Formats every file can become, in a fixed order; none when one of them can't convert.
    public static func formats(forExtensions exts: [String]) -> [ConvertFormat] {
        guard !exts.isEmpty else { return [] }
        let kinds = exts.map(kind(ofExtension:))
        var shared = formats(for: kinds[0])
        for kind in kinds.dropFirst() {
            let allowed = Set(formats(for: kind))
            shared = shared.filter(allowed.contains)
        }
        let sources = Set(exts.map(normalised))
        if sources.count == 1, let only = sources.first {
            shared.removeAll { $0.ext == only }
        }
        return Array(shared.prefix(8))
    }

    /// The sub-ring: one numbered entry per format, then the panel.
    public static func choices(for formats: [ConvertFormat]) -> [RingChoice] {
        guard !formats.isEmpty else { return [] }
        return formats.enumerated().map { index, format in
            RingChoice(id: prefix + format.rawValue, title: "\(index + 1)  \(format.title)", symbol: format.symbol)
        } + [RingChoice(id: moreID, title: "More…", symbol: "slider.horizontal.3")]
    }

    /// The format a convert choice stands for; nil for "More…" and any other choice.
    public static func format(of choice: RingChoice) -> ConvertFormat? {
        guard choice.id.hasPrefix(prefix) else { return nil }
        return ConvertFormat(rawValue: String(choice.id.dropFirst(prefix.count)))
    }

    private static func normalised(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg": "jpg"
        case "tif": "tiff"
        case "aif": "aiff"
        default: ext.lowercased()
        }
    }
}

/// Which frames of a video become a GIF: evenly spaced, at most `fps` a second, and only the
/// first `cap` seconds, so a long clip doesn't become an enormous file.
public enum GIFPlan {
    public static let fps: Double = 10
    public static let cap: Double = 15
    public static let longestSide: CGFloat = 480

    public static func frames(duration: Double, fps: Double = fps, cap: Double = cap) -> [Double] {
        guard duration.isFinite, duration > 0, fps > 0 else { return [] }
        let length = min(duration, cap)
        let count = max(Int((length * fps).rounded(.down)), 1)
        return (0..<count).map { Double($0) / fps }
    }

    /// How long each frame shows, in seconds.
    public static func delay(fps: Double = fps) -> Double { fps > 0 ? 1 / fps : 0.1 }
}
