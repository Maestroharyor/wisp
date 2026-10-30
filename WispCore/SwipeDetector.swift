import Foundation

public enum Swipe: Sendable, Equatable {
    case up
    case down
    case left
    case right
}

/// Turns trackpad scroll deltas into one swipe per gesture. Call `reset()` when the
/// gesture ends. dy is negative when two fingers move down (natural scrolling off).
public struct SwipeDetector: Sendable {
    private var dx: Double = 0
    private var dy: Double = 0
    private var fired = false
    public var threshold: Double

    public init(threshold: Double = 40) {
        self.threshold = threshold
    }

    public mutating func add(dx: Double, dy: Double) -> Swipe? {
        guard !fired else { return nil }
        self.dx += dx
        self.dy += dy
        let horizontal = abs(self.dx)
        let vertical = abs(self.dy)
        // One axis must clearly win, so a diagonal doesn't skip a track by accident.
        guard max(horizontal, vertical) >= threshold, max(horizontal, vertical) >= 1.5 * min(horizontal, vertical)
        else { return nil }
        fired = true
        if horizontal > vertical { return self.dx > 0 ? .right : .left }
        return self.dy > 0 ? .up : .down
    }

    public mutating func reset() {
        dx = 0
        dy = 0
        fired = false
    }
}
