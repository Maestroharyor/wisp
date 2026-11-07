import Foundation

/// A subscription usage window: Claude's from the status bar, Codex's from its rollout.
public enum LimitWindow: String, CaseIterable, Sendable {
    case fiveHour
    case sevenDay

    var name: String {
        switch self {
        case .fiveHour: "5 h"
        case .sevenDay: "Weekly"
        }
    }

    /// Codex names a window by its length.
    init?(minutes: Int) {
        switch minutes {
        case 300: self = .fiveHour
        case 10_080: self = .sevenDay
        default: return nil
        }
    }
}

/// How much of a window is used, 0 to 100, and when it starts over.
public struct UsageReading: Equatable, Sendable {
    public let window: LimitWindow
    public let percent: Double
    public let resets: Date?
    /// Whose plan the window belongs to.
    public let source: AgentSource

    public init(window: LimitWindow, percent: Double, resets: Date?, source: AgentSource = .claude) {
        self.window = window
        self.percent = percent
        self.resets = resets
        self.source = source
    }
}

public enum UsageLimits {
    /// The windows a snapshot reports, five-hour first. Only Pro, Max and Ultra plans get
    /// them, and either can be missing.
    public static func readings(_ extras: StatusLineSnapshot.Extras) -> [UsageReading] {
        [
            extras.fiveHourPercent.map { UsageReading(window: .fiveHour, percent: $0, resets: extras.fiveHourResets) },
            extras.sevenDayPercent.map { UsageReading(window: .sevenDay, percent: $0, resets: extras.sevenDayResets) },
        ]
        .compactMap { $0 }
    }

    /// Codex's `rate_limits` from a rollout `token_count` event: `primary` and `secondary`, each
    /// with `used_percent`, `window_minutes` and `resets_at` (epoch seconds). Older rollouts
    /// give `resets_in_seconds`, counted from the line's `timestamp`.
    public static func codexReadings(_ limits: JSONValue?, at timestamp: Date?) -> [UsageReading] {
        ["primary", "secondary"].compactMap { key in
            guard let entry = limits?[key], let percent = entry["used_percent"]?.doubleValue,
                let window = entry["window_minutes"]?.intValue.flatMap(LimitWindow.init(minutes:))
            else { return nil }
            let resets =
                entry["resets_at"]?.doubleValue.map(Date.init(timeIntervalSince1970:))
                ?? entry["resets_in_seconds"]?.doubleValue.flatMap { seconds in timestamp.map { $0 + seconds } }
            return UsageReading(window: window, percent: percent, resets: resets, source: .codex)
        }
    }

    /// `current` with one agent's readings swapped for its latest: Claude Code's first, and
    /// each agent's five-hour window before its weekly one.
    public static func merge(_ current: [UsageReading], with latest: [UsageReading]) -> [UsageReading] {
        let sources = Set(latest.map(\.source))
        return (current.filter { !sources.contains($0.source) } + latest).sorted { rank($0) < rank($1) }
    }

    private static func rank(_ reading: UsageReading) -> Int {
        let agent = AgentAdapters.all.firstIndex { $0.source == reading.source } ?? 0
        return agent * LimitWindow.allCases.count + (LimitWindow.allCases.firstIndex(of: reading.window) ?? 0)
    }
}

/// A window passing one of the alert levels.
public struct LimitAlert: Equatable, Sendable {
    public let window: LimitWindow
    public let level: Double
    public let percent: Double
    public let resets: Date?
    public var source: AgentSource = .claude

    /// Short enough for the pill ("5 h limit 82%"); the reset time is in the session's
    /// details and `wisp status`. Claude Code's windows came first, so only others are named.
    public var text: String {
        let agent = source == .claude ? "" : source.displayName + " "
        return "\(agent)\(window.name) limit \(Int(percent.rounded()))%"
    }
}

/// Follows the usage windows across snapshots: alerts once per level in each agent's
/// window, starting again when the window resets, and projects when it will run out.
public struct LimitWatch: Sendable {
    public static let levels: [Double] = [80, 95]
    /// A rate measured over less than this is noise.
    static let minimumStretch: TimeInterval = 300
    /// Only the last hour of use decides the pace.
    static let paceWindow: TimeInterval = 3600

    private struct Track: Sendable {
        var resets: Date?
        var fired: Double = 0
        var samples: [(date: Date, percent: Double)] = []
    }

    private struct Key: Hashable, Sendable {
        let source: AgentSource
        let window: LimitWindow
    }

    private var tracks: [Key: Track] = [:]

    public init() {}

    /// Takes in the latest readings and returns the alerts now due. Levels already passed
    /// are marked even when alerts are off, so turning them on later stays quiet.
    public mutating func record(_ readings: [UsageReading], at date: Date) -> [LimitAlert] {
        var due: [LimitAlert] = []
        for reading in readings {
            let key = Key(source: reading.source, window: reading.window)
            var track = tracks[key] ?? Track(resets: reading.resets)
            // A new reset time means a fresh window. Without one, only a fall in usage can say
            // so; with one, a lower figure is just another session's older snapshot.
            let lastPercent = track.samples.last?.percent ?? 0
            let fell = reading.resets == nil && reading.percent < lastPercent - 1
            if track.resets != reading.resets || fell {
                track = Track(resets: reading.resets)
            }
            if reading.percent < lastPercent, !fell, !track.samples.isEmpty {
                tracks[key] = track
                continue
            }
            track.samples.append((date, reading.percent))
            track.samples.removeAll { date.timeIntervalSince($0.date) > Self.paceWindow }
            if let level = Self.levels.last(where: { reading.percent >= $0 }), level > track.fired {
                track.fired = level
                due.append(
                    LimitAlert(
                        window: reading.window, level: level, percent: reading.percent, resets: reading.resets,
                        source: reading.source))
            }
            tracks[key] = track
        }
        return due
    }

    /// When the window will be used up at the pace of the last hour; nil when it isn't
    /// rising, the stretch is too short to tell, or it resets first.
    public func forecast(_ window: LimitWindow, source: AgentSource = .claude) -> Date? {
        guard let track = tracks[Key(source: source, window: window)], let first = track.samples.first,
            let last = track.samples.last
        else { return nil }
        let elapsed = last.date.timeIntervalSince(first.date)
        let rise = last.percent - first.percent
        guard elapsed >= Self.minimumStretch, rise > 0, last.percent < 100 else { return nil }
        let full = last.date.addingTimeInterval((100 - last.percent) / rise * elapsed)
        if let resets = track.resets, full >= resets { return nil }
        return full
    }

    /// A time of day in the user's 12 or 24 hour style.
    public static func clock(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }
}
