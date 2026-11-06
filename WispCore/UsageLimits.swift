import Foundation

/// A Claude subscription usage window, as the status bar reports it.
public enum LimitWindow: String, CaseIterable, Sendable {
    case fiveHour
    case sevenDay

    var name: String {
        switch self {
        case .fiveHour: "5 h"
        case .sevenDay: "Weekly"
        }
    }
}

/// How much of a window is used, 0 to 100, and when it starts over.
public struct UsageReading: Equatable, Sendable {
    public let window: LimitWindow
    public let percent: Double
    public let resets: Date?

    public init(window: LimitWindow, percent: Double, resets: Date?) {
        self.window = window
        self.percent = percent
        self.resets = resets
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
}

/// A window passing one of the alert levels.
public struct LimitAlert: Equatable, Sendable {
    public let window: LimitWindow
    public let level: Double
    public let percent: Double
    public let resets: Date?

    /// Short enough for the pill ("5 h limit 82%"); the reset time is in the session's
    /// details and `wisp status`.
    public var text: String { "\(window.name) limit \(Int(percent.rounded()))%" }
}

/// Follows the usage windows across status bar snapshots: alerts once per level in each
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

    private var tracks: [LimitWindow: Track] = [:]

    public init() {}

    /// Takes in the latest readings and returns the alerts now due. Levels already passed
    /// are marked even when alerts are off, so turning them on later stays quiet.
    public mutating func record(_ readings: [UsageReading], at date: Date) -> [LimitAlert] {
        var due: [LimitAlert] = []
        for reading in readings {
            var track = tracks[reading.window] ?? Track(resets: reading.resets)
            // A new reset time, or usage falling back, means a fresh window.
            let lastPercent = track.samples.last?.percent ?? 0
            if track.resets != reading.resets || reading.percent < lastPercent - 1 {
                track = Track(resets: reading.resets)
            }
            track.samples.append((date, reading.percent))
            track.samples.removeAll { date.timeIntervalSince($0.date) > Self.paceWindow }
            if let level = Self.levels.last(where: { reading.percent >= $0 }), level > track.fired {
                track.fired = level
                due.append(
                    LimitAlert(window: reading.window, level: level, percent: reading.percent, resets: reading.resets))
            }
            tracks[reading.window] = track
        }
        return due
    }

    /// When the window will be used up at the pace of the last hour; nil when it isn't
    /// rising, the stretch is too short to tell, or it resets first.
    public func forecast(_ window: LimitWindow) -> Date? {
        guard let track = tracks[window], let first = track.samples.first, let last = track.samples.last else {
            return nil
        }
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
