import Foundation

/// A Keep awake that may end on its own: indefinitely, for a length of time, or until a time
/// of day.
public struct KeepAwakeSession: Equatable, Sendable {
    public let started: Date
    /// Nil keeps the Mac awake until it's switched off.
    public let ends: Date?

    public init(started: Date, ends: Date?) {
        self.started = started
        self.ends = ends
    }

    /// A session of `length` seconds from `now`; nil or a length of zero or less never ends.
    public static func lasting(_ length: TimeInterval?, from now: Date) -> KeepAwakeSession {
        guard let length, length > 0 else { return KeepAwakeSession(started: now, ends: nil) }
        return KeepAwakeSession(started: now, ends: now.addingTimeInterval(length))
    }

    /// A session ending at the next `hour`:`minute`: later today, or tomorrow once it has passed.
    /// A time the calendar can't find lasts a day rather than never ending.
    public static func until(hour: Int, minute: Int, from now: Date, calendar: Calendar = .current)
        -> KeepAwakeSession
    {
        let time = DateComponents(hour: hour, minute: minute, second: 0)
        let end = calendar.nextDate(after: now, matching: time, matchingPolicy: .nextTime)
        return KeepAwakeSession(started: now, ends: end ?? now.addingTimeInterval(24 * 3600))
    }

    /// Seconds left, never below zero; nil for a session with no end.
    public func remaining(now: Date) -> TimeInterval? {
        ends.map { max($0.timeIntervalSince(now), 0) }
    }

    public func isExpired(now: Date) -> Bool {
        ends.map { now >= $0 } ?? false
    }
}
