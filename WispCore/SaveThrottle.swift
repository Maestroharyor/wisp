import Foundation

/// When state that changes often is written out: only after a change, and at most once per
/// `interval`. The caller saves when `wait` reaches zero, then calls `saved(at:)`.
public struct SaveThrottle: Equatable, Sendable {
    public let interval: TimeInterval
    /// A change hasn't been saved yet.
    public private(set) var isPending = false
    private var lastSave: Date?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public mutating func markChanged() { isPending = true }

    public mutating func saved(at date: Date) {
        isPending = false
        lastSave = date
    }

    /// Seconds until the pending change should be saved: zero for now, nil with nothing to save.
    public func wait(now: Date) -> TimeInterval? {
        guard isPending else { return nil }
        guard let lastSave else { return 0 }
        let age = now.timeIntervalSince(lastSave)
        // A negative age means the clock moved back, so waiting could last that long.
        guard age >= 0 else { return 0 }
        return max(0, interval - age)
    }
}
