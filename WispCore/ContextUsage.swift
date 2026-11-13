import Foundation

/// How full an agent's context window is, and when to tell the user about it.
public enum ContextUsage {
    public enum Level: Equatable, Sendable {
        case normal
        case warning
        case critical
    }

    /// Where the gauge turns amber (`warn`, which is also when the alert fires) and red. Critical
    /// is always above warn, so the two colours never swap.
    public struct Thresholds: Equatable, Sendable {
        public static let warnRange: ClosedRange<Double> = 50...95
        /// The smallest step between warn and critical.
        public static let gap = 5.0
        public static let standard = Thresholds(warn: 70, critical: 90)

        public let warn: Double
        public let critical: Double

        public init(warn: Double, critical: Double) {
            let warn = min(max(warn, Self.warnRange.lowerBound), Self.warnRange.upperBound)
            self.warn = warn
            self.critical = min(max(critical, warn + Self.gap), 100)
        }

        /// Settings keys, shared by Wisp and the helper's terminal bar.
        public static let warnKey = "contextWarnPercent"
        public static let criticalKey = "contextCriticalPercent"
        /// Earlier versions' alert percentage, read as warn until warn is set.
        public static let legacyAlertKey = "contextThreshold"

        /// The stored settings, with the alert's own percentage from earlier versions read as
        /// warn until warn is set.
        public static func migrated(alertAt: Double?, warn: Double?, critical: Double?) -> Thresholds {
            Thresholds(warn: warn ?? alertAt ?? standard.warn, critical: critical ?? standard.critical)
        }

        /// From settings, where `read` gives a key's number or nil when it isn't set.
        public static func stored(_ read: (String) -> Double?) -> Thresholds {
            migrated(alertAt: read(legacyAlertKey), warn: read(warnKey), critical: read(criticalKey))
        }
    }

    public static func level(_ percent: Double, thresholds: Thresholds = .standard) -> Level {
        if percent >= thresholds.critical { return .critical }
        if percent >= thresholds.warn { return .warning }
        return .normal
    }

    /// Whether to alert now, and whether the session counts as alerted afterwards. An alert
    /// fires once per climb past the threshold and re-arms only after usage drops below it
    /// (usually after compaction). An unknown percentage changes nothing.
    public static func alert(percent: Double?, threshold: Double, alerted: Bool) -> (fire: Bool, alerted: Bool) {
        guard let percent else { return (false, alerted) }
        if percent < threshold { return (false, false) }
        return (!alerted, true)
    }

    /// The alert's notice ("86% · api"): short enough for the side of the pill, where the
    /// gauge says it's the context.
    public static func notice(percent: Double, project: String) -> String {
        "\(Int(percent.rounded()))% · \(project)"
    }
}
