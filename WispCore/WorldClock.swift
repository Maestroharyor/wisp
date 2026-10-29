import Foundation

/// Labels for the World Clocks widget.
public enum WorldClock {
    /// "+5h 30m" style difference from the local time zone.
    public static func offsetLabel(seconds: Int) -> String {
        guard seconds != 0 else { return "Same time" }
        let sign = seconds > 0 ? "+" : "−"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours)h \(rest)m"
    }

    /// "America/New_York" → "New York".
    public static func cityName(_ identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    public static func isDaytime(hour: Int) -> Bool { (6...18).contains(hour) }
}
