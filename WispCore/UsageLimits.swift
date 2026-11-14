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

/// A window passing the alert level or 95%, running out, or starting over.
public struct LimitAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Passed the alert level or 95%.
        case level
        /// Used up.
        case exhausted
        /// Started over after it had passed the alert level.
        case reset
    }

    public let window: LimitWindow
    public let level: Double
    public let percent: Double
    public let resets: Date?
    public var source: AgentSource = .claude
    public var kind: Kind = .level

    /// Short enough for the pill ("5 h limit 82%"); the reset time is in the session's
    /// details and `wisp status`. Claude Code's windows came first, so only others are named.
    public var text: String {
        let agent = source == .claude ? "" : source.displayName + " "
        switch kind {
        case .level: return "\(agent)\(window.name) limit \(Int(percent.rounded()))%"
        case .exhausted: return "\(agent)\(window.name) limit used up"
        case .reset: return "Your \(agent)\(window.lowercasedName) limit reset"
        }
    }

    public var symbol: String {
        switch kind {
        case .level: "gauge.with.dots.needle.67percent"
        case .exhausted: "gauge.with.dots.needle.100percent"
        case .reset: "arrow.counterclockwise"
        }
    }

    public var sound: AgentSoundEvent {
        switch kind {
        case .level: .limitWarning
        case .exhausted: .limitReached
        case .reset: .limitReset
        }
    }
}

extension LimitWindow {
    /// For the middle of a sentence ("Your weekly limit reset").
    var lowercasedName: String {
        switch self {
        case .fiveHour: "5 h"
        case .sevenDay: "weekly"
        }
    }
}

/// Follows the usage windows across snapshots: alerts once per level in each agent's window
/// (the alert level, 95% and used up), starting again when the window resets; says when a
/// window that had passed the alert level starts over; and projects when it will run out.
public struct LimitWatch: Sendable {
    public static let defaultThreshold: Double = 80
    /// Where the alert level can be set in Settings.
    public static let thresholdRange: ClosedRange<Double> = 50...95
    /// The second warning, whatever the alert level.
    public static let critical: Double = 95
    public static let exhausted: Double = 100
    /// A rate measured over less than this is noise.
    static let minimumStretch: TimeInterval = 300
    /// Only the last hour of use decides the pace.
    static let paceWindow: TimeInterval = 3600
    /// Reset times this close are the same window: older Codex rollouts give the time left,
    /// which drifts by a second or two between lines.
    static let resetTolerance: TimeInterval = 120

    private struct Track: Sendable {
        var resets: Date?
        var fired: Double = 0
        /// The start over was already announced, so the next reading doesn't announce it again.
        var resetAnnounced = false
        var samples: [(date: Date, percent: Double)] = []

        var owesReset: Bool { fired > 0 && !resetAnnounced }
    }

    private struct Key: Hashable, Sendable {
        let source: AgentSource
        let window: LimitWindow
    }

    private var tracks: [Key: Track] = [:]

    /// The first alert level, from Settings; 95% and used up always follow it.
    public var threshold: Double {
        didSet { threshold = Self.clamp(threshold) }
    }

    public init(threshold: Double = LimitWatch.defaultThreshold) {
        self.threshold = Self.clamp(threshold)
    }

    private static func clamp(_ level: Double) -> Double {
        min(max(level, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    var levels: [Double] { Set([threshold, Self.critical, Self.exhausted]).sorted() }

    /// A usage bar's colour step: amber from the alert level the user set, red from 95%, so the
    /// bar turns when the alert fires.
    public static func level(percent: Double, threshold: Double) -> ContextUsage.Level {
        if percent >= critical { return .critical }
        return percent >= clamp(threshold) ? .warning : .normal
    }

    /// Takes in the latest readings and returns the alerts now due. Levels already passed
    /// are marked even when alerts are off, so turning them on later stays quiet.
    public mutating func record(_ readings: [UsageReading], at date: Date) -> [LimitAlert] {
        var due: [LimitAlert] = []
        for reading in readings {
            let key = Key(source: reading.source, window: reading.window)
            var track = tracks[key] ?? Track(resets: reading.resets)
            // A reading from a window that already ended (another session's old snapshot) says nothing new.
            if let resets = reading.resets, let current = track.resets,
                resets < current.addingTimeInterval(-Self.resetTolerance)
            {
                continue
            }
            // A new reset time means a fresh window. Without one, only a fall in usage can say
            // so; with one, a lower figure is just another session's older snapshot.
            let lastPercent = track.samples.last?.percent ?? 0
            let fell = reading.resets == nil && reading.percent < lastPercent - 1
            // A snapshot that only adds or drops the reset time (another session, another
            // version) is the same window unless usage fell.
            if track.resets == nil, reading.resets != nil, reading.percent >= lastPercent - 1 {
                track.resets = reading.resets
            }
            let newWindow = reading.resets != nil && !Self.sameReset(track.resets, reading.resets)
            if newWindow || fell {
                if track.owesReset { due.append(alert(.reset, reading, level: 0)) }
                track = Track(resets: reading.resets)
            }
            if reading.percent < lastPercent, !fell, !track.samples.isEmpty {
                tracks[key] = track
                continue
            }
            track.samples.append((date, reading.percent))
            track.samples.removeAll { date.timeIntervalSince($0.date) > Self.paceWindow }
            if let level = levels.last(where: { reading.percent >= $0 }), level > track.fired {
                track.fired = level
                due.append(alert(level >= Self.exhausted ? .exhausted : .level, reading, level: level))
            }
            tracks[key] = track
        }
        return due
    }

    /// Windows whose reset time has come since they passed the alert level, each announced once.
    /// Readings stop while no session runs, so the clock has to notice the reset too.
    public mutating func resetsDue(at date: Date) -> [LimitAlert] {
        var due: [LimitAlert] = []
        for (key, var track) in tracks {
            guard track.owesReset, let resets = track.resets, resets <= date else { continue }
            track.resetAnnounced = true
            tracks[key] = track
            due.append(
                LimitAlert(window: key.window, level: 0, percent: 0, resets: resets, source: key.source, kind: .reset))
        }
        return due.sorted { ($0.resets ?? date) < ($1.resets ?? date) }
    }

    /// The soonest reset still to announce, so a timer can wake for it.
    public var nextReset: Date? {
        tracks.values.filter(\.owesReset).compactMap(\.resets).min()
    }

    private func alert(_ kind: LimitAlert.Kind, _ reading: UsageReading, level: Double) -> LimitAlert {
        LimitAlert(
            window: reading.window, level: level, percent: reading.percent, resets: reading.resets,
            source: reading.source, kind: kind)
    }

    private static func sameReset(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.timeIntervalSince(rhs)) <= resetTolerance
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
