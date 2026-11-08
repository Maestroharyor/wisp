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

    // MARK: Cities

    /// The most cities kept; the window shows all of them.
    public static let maximumCities = 8
    /// The notch's widget shows the first few.
    public static let notchCities = 3

    /// Saved identifiers without blanks (Settings keeps empty slots) or repeats, at most
    /// `maximumCities`.
    public static func cities(_ saved: [String]) -> [String] {
        var seen: Set<String> = []
        return Array(saved.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(maximumCities))
    }

    /// `identifier` added at the end, unless it's already there or the list is full.
    public static func adding(_ identifier: String, to saved: [String]) -> [String] {
        let list = cities(saved)
        guard !identifier.isEmpty, !list.contains(identifier), list.count < maximumCities else { return list }
        return list + [identifier]
    }

    public static func removing(_ identifier: String, from saved: [String]) -> [String] {
        cities(saved).filter { $0 != identifier }
    }

    /// `identifier` moved `offset` places (negative is towards the start), stopping at the ends.
    public static func moving(_ identifier: String, by offset: Int, in saved: [String]) -> [String] {
        var list = cities(saved)
        guard let index = list.firstIndex(of: identifier) else { return list }
        let target = min(max(index + offset, 0), list.count - 1)
        list.remove(at: index)
        list.insert(identifier, at: target)
        return list
    }

    // MARK: Time shift

    /// The time-shift slider moves in quarter hours.
    public static let shiftStep = 15
    /// Up to 12 hours either way.
    public static let shiftRange = -720...720

    /// A slider value in minutes, snapped to `shiftStep` and kept within `shiftRange`.
    public static func snappedShift(minutes: Double) -> Int {
        let snapped = Int((minutes / Double(shiftStep)).rounded()) * shiftStep
        return min(max(snapped, shiftRange.lowerBound), shiftRange.upperBound)
    }

    /// The moment the cards show while shifted: `base` to the minute, moved `minutes`.
    public static func shiftedTime(base: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.dateInterval(of: .minute, for: base)?.start ?? base
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    // MARK: Analog face

    /// Hand angles in degrees, clockwise from 12.
    public static func handAngles(hour: Int, minute: Int) -> (hour: Double, minute: Double) {
        (Double(hour % 12) * 30 + Double(minute) * 0.5, Double(minute) * 6)
    }
}
