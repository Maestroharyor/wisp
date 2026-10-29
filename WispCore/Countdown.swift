import Foundation

/// A pausable countdown, kept as plain values so it survives relaunch and is testable.
public struct Countdown: Codable, Sendable, Equatable {
    public var duration: TimeInterval
    /// Set while running.
    public private(set) var startedAt: Date?
    /// Time already counted before the latest start.
    public private(set) var elapsedBeforeStart: TimeInterval = 0

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    public var isRunning: Bool { startedAt != nil }

    public func elapsed(now: Date) -> TimeInterval {
        elapsedBeforeStart + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    public func remaining(now: Date) -> TimeInterval {
        max(duration - elapsed(now: now), 0)
    }

    /// 0 at the start, 1 when finished.
    public func progress(now: Date) -> Double {
        duration > 0 ? min(elapsed(now: now) / duration, 1) : 1
    }

    public func isFinished(now: Date) -> Bool { remaining(now: now) <= 0 }

    /// Started at some point and not reset since.
    public var hasStarted: Bool { isRunning || elapsedBeforeStart > 0 }

    public func endDate(now: Date) -> Date? {
        isRunning ? now.addingTimeInterval(remaining(now: now)) : nil
    }

    public mutating func start(now: Date) {
        guard !isRunning, !isFinished(now: now) else { return }
        startedAt = now
    }

    public mutating func pause(now: Date) {
        guard let startedAt else { return }
        elapsedBeforeStart += now.timeIntervalSince(startedAt)
        self.startedAt = nil
    }

    public mutating func reset() {
        startedAt = nil
        elapsedBeforeStart = 0
    }

    /// "25:00", or "1:05:00" past an hour. Rounds up so it never shows 0:00 while running.
    public static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
