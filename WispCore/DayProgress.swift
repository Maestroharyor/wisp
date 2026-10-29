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
        let (start, end) = bounds(on: day)
        let length = end.timeIntervalSince(start)
        return events.compactMap { event in
            guard event.upperBound > start, event.lowerBound < end else { return nil }
            let lower = clamp(event.lowerBound.timeIntervalSince(start) / length)
            let upper = clamp(event.upperBound.timeIntervalSince(start) / length)
            return lower...upper
        }
    }

    private func bounds(on date: Date) -> (Date, Date) {
        let midnight = calendar.startOfDay(for: date)
        return (
            midnight.addingTimeInterval(TimeInterval(startHour * 3600)),
            midnight.addingTimeInterval(TimeInterval(endHour * 3600))
        )
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
