import Foundation

/// Estimated agent spend per calendar day, kept for a month.
public struct DailySpend: Codable, Equatable, Sendable {
    public static let keptDays = 30

    /// Dollars by day, keyed "yyyy-MM-dd".
    public private(set) var days: [String: Double] = [:]

    public init() {}

    public mutating func add(_ dollars: Double, on date: Date, calendar: Calendar = .current) {
        guard dollars > 0 else { return }
        days[Self.key(date, calendar), default: 0] += dollars
        if days.count > Self.keptDays {
            // Keys sort by date, so the oldest come first.
            for key in days.keys.sorted().prefix(days.count - Self.keptDays) { days[key] = nil }
        }
    }

    public func total(on date: Date, calendar: Calendar = .current) -> Double {
        days[Self.key(date, calendar)] ?? 0
    }

    /// Spend for each of the `days` days up to and including `ending`, oldest first.
    public func recent(days count: Int, ending date: Date, calendar: Calendar = .current) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { back in
            calendar.date(byAdding: .day, value: -back, to: date).map { total(on: $0, calendar: calendar) } ?? 0
        }
    }

    public func total(lastDays count: Int, ending date: Date, calendar: Calendar = .current) -> Double {
        recent(days: count, ending: date, calendar: calendar).reduce(0, +)
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
