import Foundation

/// Per-app volume, saved by bundle id. Only apps turned down or muted are stored; an app
/// Wisp hasn't seen yet plays at full volume, and Wisp never touches it.
public struct AppVolumeSettings: Sendable, Equatable, Codable {
    /// Levels below full, 0 to 1.
    public private(set) var levels: [String: Double] = [:]
    public private(set) var muted: Set<String> = []

    /// Levels this close to full count as full, so a slider dragged back to the top lets go of the app.
    private static let snap = 0.01

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decodeIfPresent([String: Double].self, forKey: .levels) ?? [:]
        muted = try container.decodeIfPresent(Set<String>.self, forKey: .muted) ?? []
        for (app, level) in stored { setLevel(level, for: app) }
    }

    public func level(for app: String) -> Double { levels[app] ?? 1 }

    public func isMuted(_ app: String) -> Bool { muted.contains(app) }

    public mutating func setLevel(_ level: Double, for app: String) {
        let clamped = level.isFinite ? min(max(level, 0), 1) : 1
        levels[app] = clamped >= 1 - Self.snap ? nil : clamped
    }

    public mutating func setMuted(_ isMuted: Bool, for app: String) {
        if isMuted { muted.insert(app) } else { muted.remove(app) }
    }

    public mutating func reset(_ app: String) {
        levels[app] = nil
        muted.remove(app)
    }

    /// The amplitude to play `app` at. Squared, so half way on the slider sounds about half as loud.
    public func gain(for app: String) -> Float {
        if isMuted(app) { return 0 }
        let level = level(for: app)
        return Float(level * level)
    }

    /// Only apps below full volume are tapped; the rest play untouched.
    public func needsTap(_ app: String) -> Bool { gain(for: app) < 1 }

    /// Every app Wisp should be scaling, sorted.
    public var tappedApps: [String] { Set(levels.keys).union(muted).sorted() }
}

/// One process with an audio connection, as CoreAudio lists it.
public struct AudioProcess: Sendable, Equatable {
    /// CoreAudio's process object id, which a tap is built from.
    public var objectID: UInt32
    /// The app it plays for (see `AudioAppGrouping`), nil for system processes.
    public var appID: String?
    /// Whether it's sending audio out right now.
    public var isPlaying: Bool

    public init(objectID: UInt32, appID: String?, isPlaying: Bool) {
        self.objectID = objectID
        self.appID = appID
        self.isPlaying = isPlaying
    }
}

/// Which app a process's sound belongs to. Browsers and Electron apps play from helper
/// processes, so those fold into their app.
public enum AudioAppGrouping {
    /// System processes that play alerts or listen for Siri, never shown as apps.
    private static let system: Set<String> = [
        "systemsoundserverd", "com.apple.controlcenter", "com.apple.mediaremoted", "com.apple.audiomxd",
        "com.apple.CoreSpeech", "com.apple.assistantd", "com.apple.accessibility.heard",
        "com.apple.universalaccessd", "com.apple.avconferenced", "com.apple.TelephonyUtilities",
        "com.apple.cmio.ContinuityCaptureAgent",
    ]

    /// `process` is the process's bundle id; `ancestors` are the bundle ids of the regular
    /// apps above it, nearest first.
    public static func appID(process: String, ancestors: [String]) -> String? {
        if let owner = ancestors.first(where: { !$0.isEmpty }) { return owner }
        guard !process.isEmpty, !system.contains(process) else { return nil }
        // Safari and other apps' web views play through WebKit's shared processes.
        if process.hasPrefix("com.apple.WebKit.") { return "com.apple.Safari" }
        let parts = process.split(separator: ".")
        if let helper = parts.firstIndex(where: { $0.lowercased().hasPrefix("helper") }), helper > 0 {
            return parts[..<helper].joined(separator: ".")
        }
        return process
    }
}

/// One row of the app volume list.
public struct AppVolumeRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var processes: [UInt32]
    public var isPlaying: Bool
    public var level: Double
    public var muted: Bool
}

public enum AppVolumeList {
    /// Apps playing now, plus quiet ones that still have a level of their own. Playing apps
    /// first, then by name. `names` maps bundle ids to display names.
    public static func rows(
        processes: [AudioProcess], settings: AppVolumeSettings, ownAppID: String?, names: [String: String]
    ) -> [AppVolumeRow] {
        let groups = Dictionary(grouping: processes.filter { $0.appID != nil && $0.appID != ownAppID }) {
            $0.appID ?? ""
        }
        let rows = groups.compactMap { app, members -> AppVolumeRow? in
            let playing = members.contains(where: \.isPlaying)
            guard playing || settings.needsTap(app) else { return nil }
            return AppVolumeRow(
                id: app, name: names[app] ?? app, processes: members.map(\.objectID).sorted(), isPlaying: playing,
                level: settings.level(for: app), muted: settings.isMuted(app))
        }
        return rows.sorted {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

/// Which taps should exist: one per app below full volume, covering all its processes.
public enum AppVolumeTaps {
    public static func wanted(processes: [AudioProcess], settings: AppVolumeSettings, ownAppID: String?)
        -> [String: Set<UInt32>]
    {
        var wanted: [String: Set<UInt32>] = [:]
        for process in processes {
            guard let app = process.appID, app != ownAppID, settings.needsTap(app) else { continue }
            wanted[app, default: []].insert(process.objectID)
        }
        return wanted
    }

    /// Taps to take down and taps to build. A tap whose processes changed is rebuilt.
    public static func plan(current: [String: Set<UInt32>], wanted: [String: Set<UInt32>])
        -> (remove: [String], create: [String: Set<UInt32>])
    {
        let remove = current.filter { wanted[$0.key] != $0.value }.keys.sorted()
        let create = wanted.filter { current[$0.key] != $0.value }
        return (remove, create)
    }
}

/// Decides when a tap may take over an app's sound. A tap starts out unmuted, so the app
/// keeps playing as normal; it mutes the app only after real sound has come through that
/// tap, which proves Wisp may record system audio. Without that permission a tap hears only
/// silence, and muting would leave the app silent.
public struct TapArming: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case listening
        /// Sound came through: the tap may mute the app and play it scaled.
        case armed
        /// The app has been playing but the tap hears nothing, most likely because System
        /// Audio Recording is off. Keeps listening.
        case silent
        /// Armed, but the app has played for a while with nothing coming through (the
        /// permission was turned off, or the stream changed). The tap should come down so the
        /// app plays directly.
        case lost
    }

    public private(set) var state = State.listening
    private var quietPlaying: Double = 0

    /// About -80 dB, below any real recording but above the zeros of a denied tap.
    static let threshold: Float = 0.000_1
    /// Seconds of playing with no sound before calling it silent or lost.
    static let silentAfter: Double = 3

    public init() {}

    /// `peak` is the loudest sample since the last call, `seconds` the time since then.
    public mutating func observe(peak: Float, appPlaying: Bool, seconds: Double) -> State {
        if peak > Self.threshold {
            quietPlaying = 0
            if state != .lost { state = .armed }
            return state
        }
        guard appPlaying, state != .lost else { return state }
        quietPlaying += seconds
        if quietPlaying >= Self.silentAfter {
            state = state == .armed ? .lost : .silent
        }
        return state
    }
}

/// System Audio Recording has no public status check, so Wisp judges it from its taps.
public enum SystemAudioHearing {
    /// True once any tap hears sound. False only when several taps hear nothing while their
    /// apps play, since one quiet stream (a silent video) proves little. Nil otherwise.
    public static func status(armed: Int, silent: Int) -> Bool? {
        if armed > 0 { return true }
        return silent >= 2 ? false : nil
    }
}

/// Whether a tap's audio IO should run: while its app plays, and for a short grace after,
/// so an idle app turned down costs nothing. Stopping is safe: a tap that mutes only while
/// it's read lets the app play directly the moment the reading stops.
public struct TapActivity: Sendable, Equatable {
    public private(set) var running = false
    private var quiet: Double = 0

    /// Seconds after the app stops playing before the IO stops.
    static let grace: Double = 5

    public init() {}

    /// Returns whether the IO should be running now.
    public mutating func observe(appPlaying: Bool, seconds: Double) -> Bool {
        if appPlaying {
            quiet = 0
            running = true
        } else if running {
            quiet += seconds
            if quiet >= Self.grace { running = false }
        }
        return running
    }
}

/// The app each audio process plays for, worked out once per process. Resolving walks the
/// process tree, which is too slow to repeat on every poll.
public struct AudioAppCache: Sendable {
    private struct Key: Hashable {
        let object: UInt32
        let pid: Int32
    }

    /// Optional values, so system processes (no app) are remembered too.
    private var entries: [Key: String?] = [:]

    public init() {}

    public var count: Int { entries.count }

    public mutating func appID(object: UInt32, pid: Int32, resolve: (Int32) -> String?) -> String? {
        let key = Key(object: object, pid: pid)
        if let known = entries[key] { return known }
        let found = resolve(pid)
        entries[key] = .some(found)
        return found
    }

    /// Forgets processes no longer in CoreAudio's list.
    public mutating func keep(objects: Set<UInt32>) {
        entries = entries.filter { objects.contains($0.key.object) }
    }
}

/// Copying and scaling interleaved float samples on the audio thread. No allocation.
public enum AudioGain {
    /// Writes `frames` frames from `input` into one output buffer, scaled by a gain that moves
    /// evenly from `start` to `end` across the buffer so a change never clicks. The buffer
    /// carries the device's channels from `firstChannel` on; channels the input doesn't have
    /// are silent.
    public static func render(
        _ input: UnsafeBufferPointer<Float>, channels inputChannels: Int,
        into output: UnsafeMutableBufferPointer<Float>,
        channels outputChannels: Int, firstChannel: Int = 0, frames: Int, from start: Float, to end: Float
    ) {
        guard inputChannels > 0, outputChannels > 0, frames > 0 else { return }
        let available = min(frames, input.count / inputChannels, output.count / outputChannels)
        let step = (end - start) / Float(frames)
        for frame in 0..<available {
            let gain = start + step * Float(frame + 1)
            let inBase = frame * inputChannels
            let outBase = frame * outputChannels
            for channel in 0..<outputChannels {
                let source = firstChannel + channel
                output[outBase + channel] = source < inputChannels ? input[inBase + source] * gain : 0
            }
        }
        silence(output, from: available * outputChannels, frames: frames, channels: outputChannels)
    }

    /// Like `render`, for a mono output: the input's first two channels are mixed down.
    public static func renderMono(
        _ input: UnsafeBufferPointer<Float>, channels inputChannels: Int,
        into output: UnsafeMutableBufferPointer<Float>,
        frames: Int, from start: Float, to end: Float
    ) {
        guard inputChannels > 0, frames > 0 else { return }
        let available = min(frames, input.count / inputChannels, output.count)
        let step = (end - start) / Float(frames)
        let second = min(1, inputChannels - 1)
        for frame in 0..<available {
            let gain = start + step * Float(frame + 1)
            let base = frame * inputChannels
            output[frame] = (input[base] + input[base + second]) * 0.5 * gain
        }
        silence(output, from: available, frames: frames, channels: 1)
    }

    /// Zeroes what the input couldn't fill, so the device never plays stale samples.
    private static func silence(
        _ output: UnsafeMutableBufferPointer<Float>, from written: Int, frames: Int, channels: Int
    ) {
        let total = min(frames * channels, output.count)
        guard written < total else { return }
        for index in written..<total { output[index] = 0 }
    }

    /// The loudest sample, for telling sound from the silence of a tap that can't hear.
    public static func peak(_ samples: UnsafeBufferPointer<Float>) -> Float {
        var loudest: Float = 0
        for sample in samples { loudest = max(loudest, abs(sample)) }
        return loudest
    }
}
