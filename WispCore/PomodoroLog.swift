import Foundation

/// Today's finished Pomodoro focus sessions, for the window's Today list: their times, and what
/// each was for when a reminder was dropped on the timer. Kept on this Mac only. A new day
/// starts empty.
public struct PomodoroLog: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Sendable, Identifiable {
        public let start: Date
        public let end: Date
        /// What the session was for; nil when nothing was given (and for sessions saved before
        /// labels existed).
        public let label: String?

        public var id: Date { end }
        /// Whole minutes, rounded.
        public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
    }

    /// The most sessions kept; older ones drop off.
    public static let limit = 50

    public private(set) var sessions: [Session] = []

    public init() {}

    /// Adds a finished session. Sessions from an earlier day than this one's end are dropped.
    public mutating func record(start: Date, end: Date, label: String? = nil, calendar: Calendar = .current) {
        guard end >= start else { return }
        sessions.removeAll { !calendar.isDate($0.end, inSameDayAs: end) }
        sessions.append(Session(start: start, end: end, label: label))
        if sessions.count > Self.limit { sessions.removeFirst(sessions.count - Self.limit) }
    }

    /// Forgets sessions from before `now`'s day, so what they were for isn't kept past it.
    public mutating func dropOldDays(now: Date, calendar: Calendar = .current) {
        sessions.removeAll { !calendar.isDate($0.end, inSameDayAs: now) }
    }

    /// Sessions that ended on `now`'s day, oldest first.
    public func today(now: Date, calendar: Calendar = .current) -> [Session] {
        sessions.filter { calendar.isDate($0.end, inSameDayAs: now) }
    }

    public func focusMinutes(now: Date, calendar: Calendar = .current) -> Int {
        today(now: now, calendar: calendar).reduce(0) { $0 + $1.minutes }
    }
}

/// What a Pomodoro is for, from a dropped reminder or text: its first line, kept short.
public enum PomodoroLabel {
    public static let maxLength = 60

    public static func from(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}
