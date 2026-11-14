import Foundation

/// The kinds of agent alert quiet hours can silence, each chosen on its own.
public enum AgentAlertGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Requests, questions, prompts in the terminal and the idle nudge.
    case needsYou
    /// Finished and failed turns and sessions, and cloud tasks.
    case done
    /// Context, spend cap, usage limit and budget alerts.
    case limits

    public var id: Self { self }

    public var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .done: "Done"
        case .limits: "Limits"
        }
    }
}

extension AgentSoundEvent {
    public var group: AgentAlertGroup {
        switch self {
        case .needsApproval, .question: .needsYou
        case .finished, .failed: .done
        case .contextWarning, .contextCritical, .spendCap: .limits
        }
    }
}

extension PushKind {
    public var group: AgentAlertGroup {
        switch self {
        case .approval, .needsYou: .needsYou
        case .done, .cloud: .done
        case .limit, .budget: .limits
        }
    }
}

/// A daily window when the chosen alert groups stay silent. The window may cross midnight
/// (22:00 to 07:00); the same start and end is an empty window.
public struct QuietHours: Codable, Equatable, Sendable {
    public static let minutesPerDay = 24 * 60

    public var on: Bool
    /// Minutes after midnight, 0 to 1439.
    public var start: Int {
        didSet { start = Self.clamp(start) }
    }
    public var end: Int {
        didSet { end = Self.clamp(end) }
    }
    public var groups: Set<AgentAlertGroup>

    public init(
        on: Bool = false, start: Int = 22 * 60, end: Int = 7 * 60,
        groups: Set<AgentAlertGroup> = Set(AgentAlertGroup.allCases)
    ) {
        self.on = on
        self.start = Self.clamp(start)
        self.end = Self.clamp(end)
        self.groups = groups
    }

    /// Whether `minute` (after midnight) falls inside the window, whatever `on` says.
    public func covers(minuteOfDay minute: Int) -> Bool {
        if start == end { return false }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    public func isQuiet(_ group: AgentAlertGroup, at date: Date, calendar: Calendar = .current) -> Bool {
        guard on, groups.contains(group) else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return covers(minuteOfDay: Self.minuteOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0))
    }

    public static func minuteOfDay(hour: Int, minute: Int) -> Int {
        clamp(hour * 60 + minute)
    }

    public static func hourAndMinute(_ minuteOfDay: Int) -> (hour: Int, minute: Int) {
        let value = clamp(minuteOfDay)
        return (value / 60, value % 60)
    }

    private static func clamp(_ minute: Int) -> Int {
        min(max(minute, 0), minutesPerDay - 1)
    }

    private enum CodingKeys: String, CodingKey {
        case on, start, end, groups
    }

    /// Missing keys keep their defaults and unknown groups are dropped, so a later version's
    /// value still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = QuietHours()
        on = (try? container.decode(Bool.self, forKey: .on)) ?? defaults.on
        start = Self.clamp((try? container.decode(Int.self, forKey: .start)) ?? defaults.start)
        end = Self.clamp((try? container.decode(Int.self, forKey: .end)) ?? defaults.end)
        let names = try? container.decode([String].self, forKey: .groups)
        groups = names.map { Set($0.compactMap(AgentAlertGroup.init(rawValue:))) } ?? defaults.groups
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(on, forKey: .on)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(groups.map(\.rawValue).sorted(), forKey: .groups)
    }
}

/// Whether an alert group is silent now: inside quiet hours, or while a mute ("Mute for 1 h")
/// runs, which covers every group.
public enum AlertQuiet {
    public static func isQuiet(
        _ group: AgentAlertGroup, hours: QuietHours, mutedUntil: Date?, now: Date, calendar: Calendar = .current
    ) -> Bool {
        activeMute(mutedUntil, now: now) != nil || hours.isQuiet(group, at: now, calendar: calendar)
    }

    /// The mute's end while it still runs, otherwise nil.
    public static func activeMute(_ mutedUntil: Date?, now: Date) -> Date? {
        guard let mutedUntil, mutedUntil > now else { return nil }
        return mutedUntil
    }
}
