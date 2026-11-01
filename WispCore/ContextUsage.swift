import Foundation

/// How full an agent's context window is, and when to tell the user about it.
public enum ContextUsage {
    public enum Level: Equatable, Sendable {
        case normal
        case warning
        case critical
    }

    public static let warningPercent = 70.0
    public static let criticalPercent = 90.0
    public static let defaultThreshold = 80.0

    public static func level(_ percent: Double) -> Level {
        if percent >= criticalPercent { return .critical }
        if percent >= warningPercent { return .warning }
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
}
