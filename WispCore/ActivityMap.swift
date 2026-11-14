import Foundation

/// What the activity map counts per day.
public enum ActivityMetric: String, CaseIterable, Identifiable, Sendable {
    case sessions
    case turns

    public var id: Self { self }

    public var title: String {
        switch self {
        case .sessions: "Sessions"
        case .turns: "Turns"
        }
    }

    /// "1 session", "14 turns".
    public func phrase(_ count: Int) -> String {
        switch self {
        case .sessions: count == 1 ? "1 session" : "\(count) sessions"
        case .turns: count == 1 ? "1 turn" : "\(count) turns"
        }
    }
}

/// How long the activity map's daily counts are kept, after the full records are gone.
public enum ActivityRetention: String, CaseIterable, Identifiable, Sendable {
    case threeMonths
    case oneYear
    case twoYears

    public static let standard = ActivityRetention.oneYear

    public var id: Self { self }

    public var title: String {
        switch self {
        case .threeMonths: "3 months"
        case .oneYear: "1 year"
        case .twoYears: "2 years"
        }
    }

    var months: Int {
        switch self {
        case .threeMonths: 3
        case .oneYear: 12
        case .twoYears: 24
        }
    }

    /// The first day still kept.
    public func firstDay(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .month, value: -months, to: today) ?? today
    }

    /// The most week columns the map shows; more would shrink the squares out of sight.
    public static let maxWeeks = 53

    /// Week columns from the one holding the first day kept to this week, at most `maxWeeks`.
    public func weeks(now: Date, calendar: Calendar = .current) -> Int {
        let start = { (date: Date) -> Date in
            let day = calendar.startOfDay(for: date)
            let intoWeek = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: -intoWeek, to: day) ?? day
        }
        let days = calendar.dateComponents([.day], from: start(firstDay(now: now, calendar: calendar)), to: start(now))
        return min(max((days.day ?? 0) / 7 + 1, 1), Self.maxWeeks)
    }

    /// The stretch the map covers, for its header: "in the last 3 months".
    public var shownPeriod: String {
        switch self {
        case .threeMonths: "in the last 3 months"
        case .oneYear, .twoYears: "in the last year"
        }
    }
}

/// One agent's runs on one day.
public struct ActivityCount: Codable, Equatable, Sendable {
    public var sessions: Int
    public var turns: Int

    public init(sessions: Int = 0, turns: Int = 0) {
        self.sessions = sessions
        self.turns = turns
    }

    public func value(_ metric: ActivityMetric) -> Int {
        switch metric {
        case .sessions: sessions
        case .turns: turns
        }
    }
}

/// Sessions and turns per day per agent, for the activity map. Only counts: no projects, names,
/// commands or anything else from the records. A run counts on the day it started.
public struct ActivityMap: Codable, Equatable, Sendable {
    /// Day ("2026-11-14", in the user's calendar) to agent id to its counts. Agent ids are kept as
    /// text, so an agent a later version adds survives a round trip.
    public private(set) var days: [String: [String: ActivityCount]] = [:]

    public init() {}

    public var isEmpty: Bool { days.isEmpty }

    public mutating func add(_ record: SessionRecord, calendar: Calendar = .current) {
        let day = Self.key(record.started, calendar: calendar)
        var count = days[day]?[record.source.rawValue] ?? ActivityCount()
        count.sessions += 1
        count.turns += record.turns
        days[day, default: [:]][record.source.rawValue] = count
    }

    /// This map with `records` counted too, for showing saved counts with the records still kept in full.
    public func adding(_ records: [SessionRecord], calendar: Calendar = .current) -> ActivityMap {
        var map = self
        for record in records { map.add(record, calendar: calendar) }
        return map
    }

    /// Drops days before what `retention` keeps.
    public mutating func prune(keeping retention: ActivityRetention, now: Date, calendar: Calendar = .current) {
        let first = Self.key(retention.firstDay(now: now, calendar: calendar), calendar: calendar)
        // Keys are zero-padded year-month-day, so they sort as dates do.
        days = days.filter { $0.key >= first }
    }

    /// Each known agent's counts on the day holding `date`, busiest first.
    public func breakdown(on date: Date, metric: ActivityMetric, calendar: Calendar = .current) -> [AgentTally] {
        let counts = days[Self.key(date, calendar: calendar)] ?? [:]
        return counts.compactMap { id, count in
            AgentSource(rawValue: id).map { AgentTally(source: $0, count: count.value(metric)) }
        }
        .filter { $0.count > 0 }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.source.displayName < $1.source.displayName }
    }

    /// `weeks` columns of seven days, oldest first, the last holding today. Weeks start on the
    /// calendar's first weekday; days after today are marked as future.
    public func grid(
        endingOn now: Date, weeks: Int = 53, metric: ActivityMetric, calendar: Calendar = .current
    ) -> ActivityGrid {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let intoWeek = (weekday - calendar.firstWeekday + 7) % 7
        let thisWeek = calendar.date(byAdding: .day, value: -intoWeek, to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -7 * (max(weeks, 1) - 1), to: thisWeek) ?? thisWeek
        var columns: [[ActivityDay]] = []
        for week in 0..<max(weeks, 1) {
            var column: [ActivityDay] = []
            for offset in 0..<7 {
                let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: start) ?? start
                let tallies = date > today ? [] : breakdown(on: date, metric: metric, calendar: calendar)
                column.append(
                    ActivityDay(
                        date: date, total: tallies.reduce(0) { $0 + $1.count }, tallies: tallies,
                        future: date > today))
            }
            columns.append(column)
        }
        let busiest = columns.joined().map(\.total).max() ?? 0
        return ActivityGrid(columns: columns, busiest: busiest)
    }

    static func key(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// One agent's count on a day.
public struct AgentTally: Equatable, Sendable {
    public let source: AgentSource
    public let count: Int
}

/// A cell of the activity map.
public struct ActivityDay: Equatable, Sendable {
    public let date: Date
    public let total: Int
    public let tallies: [AgentTally]
    public let future: Bool

    /// "14 turns: Claude Code 10, Codex 4", or "No sessions".
    public func summary(_ metric: ActivityMetric) -> String {
        guard total > 0 else { return metric == .sessions ? "No sessions" : "No turns" }
        let agents = tallies.map { "\($0.source.displayName) \($0.count)" }.joined(separator: ", ")
        return "\(metric.phrase(total)): \(agents)"
    }
}

public struct ActivityGrid: Equatable, Sendable {
    public static let levels = 4

    public let columns: [[ActivityDay]]
    /// The highest day's total.
    public let busiest: Int

    public var total: Int { columns.joined().reduce(0) { $0 + $1.total } }

    /// 0 for an empty day, then 1 to `levels` in even steps up to the busiest day.
    public func level(_ day: ActivityDay) -> Int {
        guard day.total > 0, busiest > 0 else { return 0 }
        let share = Double(day.total) / Double(busiest)
        return min(max(Int((share * Double(Self.levels)).rounded(.up)), 1), Self.levels)
    }
}
