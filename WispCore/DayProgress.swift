import Foundation

/// How far through the working day a moment is, and where today's events fall on it.
public struct DayProgress: Sendable {
    public let startHour: Int
    public let endHour: Int
    private let calendar: Calendar

    public init(startHour: Int, endHour: Int, calendar: Calendar = .current) {
        let valid = (0...23).contains(startHour) && (1...24).contains(endHour) && startHour < endHour
        self.startHour = valid ? startHour : 9
        self.endHour = valid ? endHour : 17
        self.calendar = calendar
    }

    public func fraction(at date: Date) -> Double {
        let (start, end) = bounds(on: date)
        return clamp(date.timeIntervalSince(start) / end.timeIntervalSince(start))
    }

    public func minutesLeft(at date: Date) -> Int {
        let (_, end) = bounds(on: date)
        return max(0, Int(end.timeIntervalSince(date) / 60))
    }

    /// Events as fractions of the day, clipped to it; events wholly outside are dropped.
    public func marks(for events: [ClosedRange<Date>], on day: Date) -> [ClosedRange<Double>] {
        events.compactMap { mark(for: $0, on: day) }
    }

    /// One event as a fraction of the day, clipped to it; nil when it's wholly outside.
    public func mark(for event: ClosedRange<Date>, on day: Date) -> ClosedRange<Double>? {
        let (start, end) = bounds(on: day)
        let length = end.timeIntervalSince(start)
        guard event.upperBound > start, event.lowerBound < end else { return nil }
        let lower = clamp(event.lowerBound.timeIntervalSince(start) / length)
        let upper = clamp(event.upperBound.timeIntervalSince(start) / length)
        return lower...upper
    }

    /// Within the working hours: from the start up to, not including, the end.
    public func isWorking(at date: Date) -> Bool {
        let (start, end) = bounds(on: date)
        return date >= start && date < end
    }

    /// When the working day next starts: today's start before it, otherwise tomorrow's.
    public func nextStart(after date: Date) -> Date {
        let (start, _) = bounds(on: date)
        guard date >= start else { return start }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        return bounds(on: tomorrow).0
    }

    /// Each whole hour of the working day with where it falls on the day, for timeline labels.
    public func hourMarks(on day: Date) -> [(hour: Int, fraction: Double)] {
        let (start, end) = bounds(on: day)
        let length = end.timeIntervalSince(start)
        return (startHour...endHour).map { hour in
            let date =
                hour == endHour ? end : calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? start
            return (hour, clamp(date.timeIntervalSince(start) / length))
        }
    }

    /// A lane for each mark, in order, so overlapping events sit on separate rows. A mark goes
    /// in the first lane whose last mark has ended by its start.
    public static func lanes(for marks: [ClosedRange<Double>]) -> [Int] {
        var ends: [Double] = []
        return marks.map { mark in
            if let lane = ends.firstIndex(where: { $0 <= mark.lowerBound }) {
                ends[lane] = mark.upperBound
                return lane
            }
            ends.append(mark.upperBound)
            return ends.count - 1
        }
    }

    private func bounds(on date: Date) -> (Date, Date) {
        // Wall-clock hours, not seconds after midnight, so a DST change doesn't shift the day.
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date) ?? date
        let end =
            endHour == 24
            ? nextMidnight(after: date) : calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date)
        return (start, end ?? start.addingTimeInterval(TimeInterval((endHour - startHour) * 3600)))
    }

    private func nextMidnight(after date: Date) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)).map(calendar.startOfDay(for:))
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
