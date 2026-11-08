import Foundation

/// Today's finished Pomodoro focus sessions, for the window's Today list. Holds only times,
/// never what the session was for. A new day starts empty.
public struct PomodoroLog: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Sendable, Identifiable {
        public let start: Date
        public let end: Date

        public var id: Date { end }
        /// Whole minutes, rounded.
        public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
    }

    /// The most sessions kept; older ones drop off.
    public static let limit = 50

    public private(set) var sessions: [Session] = []

    public init() {}

    /// Adds a finished session. Sessions from an earlier day than this one's end are dropped.
    public mutating func record(start: Date, end: Date, calendar: Calendar = .current) {
        guard end >= start else { return }
        sessions.removeAll { !calendar.isDate($0.end, inSameDayAs: end) }
        sessions.append(Session(start: start, end: end))
        if sessions.count > Self.limit { sessions.removeFirst(sessions.count - Self.limit) }
    }

    /// Sessions that ended on `now`'s day, oldest first.
    public func today(now: Date, calendar: Calendar = .current) -> [Session] {
        sessions.filter { calendar.isDate($0.end, inSameDayAs: now) }
    }

    public func focusMinutes(now: Date, calendar: Calendar = .current) -> Int {
        today(now: now, calendar: calendar).reduce(0) { $0 + $1.minutes }
    }
}
