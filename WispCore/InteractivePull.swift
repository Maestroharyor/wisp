import Foundation

/// The give past an edge, as scroll views have: it follows closely at first and stiffens, so it
/// never passes `limit`.
public enum RubberBand {
    public static func offset(_ distance: Double, limit: Double, coefficient: Double = 0.55) -> Double {
        guard limit > 0 else { return 0 }
        let magnitude = (1 - 1 / (abs(distance) * coefficient / limit + 1)) * limit
        return distance < 0 ? -magnitude : magnitude
    }
}

/// How fast a gesture was moving when it ended, fitted over its last tenth of a second, so one
/// jittery sample doesn't decide the throw. A pause before letting go reads as no throw.
public struct VelocityTracker: Sendable {
    public let window: TimeInterval
    private var samples: [(time: Date, value: Double)] = []

    public init(window: TimeInterval = 0.1) {
        self.window = window
    }

    public mutating func add(_ value: Double, at time: Date) {
        samples.append((time, value))
        samples.removeAll { time.timeIntervalSince($0.time) > window }
    }

    public mutating func reset() { samples.removeAll() }

    /// Units per second, by least squares over the recent samples.
    public func velocity(now: Date) -> Double {
        guard let last = samples.last, now.timeIntervalSince(last.time) <= window else { return 0 }
        let recent = samples.filter { last.time.timeIntervalSince($0.time) <= window }
        guard recent.count >= 2, let first = recent.first else { return 0 }
        let xs = recent.map { $0.time.timeIntervalSince(first.time) }
        let ys = recent.map(\.value)
        let count = Double(recent.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        let spread = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard spread > 0 else { return 0 }
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        return covariance / spread
    }
}

/// Where a throw would come to rest, with the deceleration UIKit's scroll views use.
public enum Momentum {
    public static func project(_ value: Double, velocity: Double, decelerationRate: Double = 0.998) -> Double {
        value + velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }
}

/// Turns a spring's start into SwiftUI's terms: its initial velocity is a share of the
/// distance still to go, per second.
public enum SpringHandoff {
    public static func relativeVelocity(_ velocity: Double, from: Double, to: Double) -> Double {
        let distance = to - from
        guard abs(distance) > 0.0001 else { return 0 }
        return velocity / distance
    }
}

/// A pull that opens something as it goes: progress follows the gesture, stretching past fully
/// open and fully closed, and letting go settles on whichever end the throw would reach.
public struct PullTracker: Sendable {
    /// Points of pull from closed to open.
    public let travel: Double
    /// How far past either end the pull may stretch, as a share of `travel`.
    public let stretch: Double
    public private(set) var distance: Double = 0
    private var tracker = VelocityTracker()

    public struct Release: Equatable, Sendable {
        public let opens: Bool
        /// Progress per second when it was let go.
        public let velocity: Double
        /// Where it was when it was let go.
        public let progress: Double
    }

    public init(travel: Double, stretch: Double = 0.2) {
        self.travel = max(travel, 1)
        self.stretch = stretch
    }

    /// Adds a movement in points and returns the progress to show.
    public mutating func add(_ delta: Double, at time: Date) -> Double {
        distance += delta
        tracker.add(distance, at: time)
        return progress
    }

    /// 0 closed and 1 open, stretched past either end.
    public var progress: Double {
        let limit = travel * stretch
        if distance < 0 { return RubberBand.offset(distance, limit: limit) / travel }
        if distance > travel { return 1 + RubberBand.offset(distance - travel, limit: limit) / travel }
        return distance / travel
    }

    public func release(now: Date) -> Release {
        let velocity = tracker.velocity(now: now)
        let resting = Momentum.project(distance, velocity: velocity)
        return Release(opens: resting > travel / 2, velocity: velocity / travel, progress: progress)
    }
}
