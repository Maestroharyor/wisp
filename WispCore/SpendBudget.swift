import Foundation

/// The daily budget alert: a notice at 80% and at 100% of a set amount, once each per day.
/// It only informs; nothing is ever stopped.
public enum SpendBudget {
    public enum Level: Int, Codable, Comparable, Sendable {
        case warning = 80
        case reached = 100

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The level to alert about now: the highest one reached that hasn't fired today. Nil when
    /// there's nothing new or no budget.
    public static func alert(spent: Double, budget: Double, fired: Level?) -> Level? {
        guard budget > 0 else { return nil }
        let reached: Level? =
            spent >= budget ? .reached : spent >= budget * Double(Level.warning.rawValue) / 100 ? .warning : nil
        guard let reached, fired.map({ reached > $0 }) ?? true else { return nil }
        return reached
    }

    /// "80% of $20" or "Over $20": short enough for the side of the pill.
    public static func text(level: Level, budget: Double) -> String {
        switch level {
        case .warning: return "\(level.rawValue)% of \(amount(budget))"
        case .reached: return "Over \(amount(budget))"
        }
    }

    /// "$20" for whole dollars, "$12.50" otherwise.
    public static func amount(_ dollars: Double) -> String {
        dollars.rounded() == dollars ? String(format: "$%.0f", dollars) : String(format: "$%.2f", dollars)
    }

    /// The level that fired today, saved so relaunching doesn't alert again.
    public struct State: Codable, Equatable, Sendable {
        public var day: String
        public var fired: Level?

        public init(day: String = "", fired: Level? = nil) {
            self.day = day
            self.fired = fired
        }

        /// What fired on `date`'s day; a new day starts with nothing.
        public func fired(on date: Date, calendar: Calendar = .current) -> Level? {
            day == DailySpend.dayKey(date, calendar: calendar) ? fired : nil
        }

        public mutating func record(_ level: Level, on date: Date, calendar: Calendar = .current) {
            day = DailySpend.dayKey(date, calendar: calendar)
            fired = level
        }
    }
}
