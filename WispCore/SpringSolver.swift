import Foundation

/// A damped spring moving from 0 to 1, solved in closed form, for motion driven outside
/// SwiftUI (a window flying into the notch) and to know when a spring has settled.
public struct SpringSolver: Sendable {
    public let spec: SpringSpec
    /// Speed at the start, in distances per second (1 covers the whole way in a second).
    public let initialVelocity: Double

    private let omega: Double
    private let zeta: Double

    public init(_ spec: SpringSpec, initialVelocity: Double = 0) {
        self.spec = spec
        self.initialVelocity = initialVelocity
        omega = 2 * .pi / max(spec.response, 0.001)
        zeta = max(spec.dampingFraction, 0)
    }

    /// How far along the spring is at `t` seconds.
    public func value(at t: Double) -> Double {
        let v0 = initialVelocity
        if zeta < 1 {
            let wd = omega * (1 - zeta * zeta).squareRoot()
            let b = (zeta * omega - v0) / wd
            return 1 - exp(-zeta * omega * t) * (cos(wd * t) + b * sin(wd * t))
        }
        if zeta == 1 {
            return 1 - exp(-omega * t) * (1 + (omega - v0) * t)
        }
        let (r1, r2, c1, c2) = overdamped
        return 1 - (c1 * exp(r1 * t) + c2 * exp(r2 * t))
    }

    /// Speed at `t` seconds, in distances per second.
    public func velocity(at t: Double) -> Double {
        let v0 = initialVelocity
        if zeta < 1 {
            let wd = omega * (1 - zeta * zeta).squareRoot()
            let b = (zeta * omega - v0) / wd
            let decay = exp(-zeta * omega * t)
            let cosine = cos(wd * t)
            let sine = sin(wd * t)
            return decay * (zeta * omega * (cosine + b * sine) - (-wd * sine + b * wd * cosine))
        }
        if zeta == 1 {
            let decay = exp(-omega * t)
            return decay * (omega * (1 + (omega - v0) * t) - (omega - v0))
        }
        let (r1, r2, c1, c2) = overdamped
        return -(c1 * r1 * exp(r1 * t) + c2 * r2 * exp(r2 * t))
    }

    /// When it stays within `epsilon` of the end, near enough at rest.
    public func settleTime(epsilon: Double = 0.001) -> Double {
        let step = 1.0 / 240
        var last = 0.0
        var t = 0.0
        while t < 10 {
            if abs(1 - value(at: t)) >= epsilon || abs(velocity(at: t)) >= epsilon * 10 { last = t + step }
            t += step
        }
        return last
    }

    private var overdamped: (Double, Double, Double, Double) {
        let root = (zeta * zeta - 1).squareRoot()
        let r1 = -omega * (zeta - root)
        let r2 = -omega * (zeta + root)
        let c2 = (-initialVelocity - r1) / (r2 - r1)
        return (r1, r2, 1 - c2, c2)
    }
}
