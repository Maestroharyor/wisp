import Foundation

/// Estimated agent spend per calendar day, kept for a month, with a split by project.
public struct DailySpend: Codable, Equatable, Sendable {
    public static let keptDays = 30
    /// Spend with no project: recorded before projects were kept, or by a session with none.
    public static let otherProjects = "Other projects"

    /// Dollars by day, keyed "yyyy-MM-dd".
    public private(set) var days: [String: Double] = [:]
    /// Dollars by day, then by project. Can add up to less than `days`; the rest is "Other".
    public private(set) var projects: [String: [String: Double]] = [:]

    public struct ProjectSpend: Equatable, Sendable {
        public let project: String
        public let today: Double
        public let week: Double
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([String: Double].self, forKey: .days) ?? [:]
        // Absent in spend saved before projects were kept.
        projects = try container.decodeIfPresent([String: [String: Double]].self, forKey: .projects) ?? [:]
    }

    public mutating func add(_ dollars: Double, on date: Date, project: String? = nil, calendar: Calendar = .current) {
        guard dollars > 0 else { return }
        let key = Self.key(date, calendar)
        days[key, default: 0] += dollars
        if let project, !project.isEmpty { projects[key, default: [:]][project, default: 0] += dollars }
        if days.count > Self.keptDays {
            // Keys sort by date, so the oldest come first.
            for key in days.keys.sorted().prefix(days.count - Self.keptDays) { days[key] = nil }
        }
        projects = projects.filter { days[$0.key] != nil }
    }

    public func total(on date: Date, calendar: Calendar = .current) -> Double {
        days[Self.key(date, calendar)] ?? 0
    }

    /// Spend for each of the `days` days up to and including `ending`, oldest first.
    public func recent(days count: Int, ending date: Date, calendar: Calendar = .current) -> [Double] {
        guard count > 0 else { return [] }
        return dayKeys(count, ending: date, calendar: calendar).map { days[$0] ?? 0 }
    }

    public func total(lastDays count: Int, ending date: Date, calendar: Calendar = .current) -> Double {
        recent(days: count, ending: date, calendar: calendar).reduce(0, +)
    }

    /// Each project's spend on `ending` and over the `count` days to it, most first. Spend
    /// with no project comes last as `otherProjects`, so the rows add up to the total. With
    /// `top`, projects past that many are folded into `otherProjects` too.
    public func byProject(
        lastDays count: Int, ending date: Date, top: Int? = nil, calendar: Calendar = .current
    ) -> [ProjectSpend] {
        let all = allProjects(lastDays: count, ending: date, calendar: calendar)
        guard let top, all.count > top + 1 else { return all }
        let rest = all.dropFirst(top)
        let other = ProjectSpend(
            project: Self.otherProjects, today: rest.map(\.today).reduce(0, +), week: rest.map(\.week).reduce(0, +))
        return Array(all.prefix(top)) + [other]
    }

    private func allProjects(lastDays count: Int, ending date: Date, calendar: Calendar) -> [ProjectSpend] {
        let todayKey = Self.key(date, calendar)
        var week: [String: Double] = [:]
        var today: [String: Double] = [:]
        for key in dayKeys(count, ending: date, calendar: calendar) {
            let split = projects[key] ?? [:]
            var other = (days[key] ?? 0) - split.values.reduce(0, +)
            for (project, dollars) in split { week[project, default: 0] += dollars }
            if key == todayKey { for (project, dollars) in split { today[project, default: 0] += dollars } }
            // Rounding can leave a hair of difference; that isn't spend.
            if other < 0.000_1 { other = 0 }
            if other > 0 {
                week[Self.otherProjects, default: 0] += other
                if key == todayKey { today[Self.otherProjects, default: 0] += other }
            }
        }
        let rows = week.map { ProjectSpend(project: $0.key, today: today[$0.key] ?? 0, week: $0.value) }
        return rows.sorted { lhs, rhs in
            if (lhs.project == Self.otherProjects) != (rhs.project == Self.otherProjects) {
                return rhs.project == Self.otherProjects
            }
            return lhs.week != rhs.week ? lhs.week > rhs.week : lhs.project < rhs.project
        }
    }

    private func dayKeys(_ count: Int, ending date: Date, calendar: Calendar) -> [String] {
        guard count > 0 else { return [] }
        // A date that can't be worked out gets a key no day has, so there are always `count`.
        return (0..<count).reversed().map { back in
            calendar.date(byAdding: .day, value: -back, to: date).map { Self.key($0, calendar) } ?? ""
        }
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
