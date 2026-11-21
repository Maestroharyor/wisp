import CoreGraphics
import Foundation

/// A spring described the way SwiftUI's `spring(response:dampingFraction:)` takes it.
public struct SpringSpec: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }

    /// Apple's way of describing a spring (`Spring(duration:bounce:)`): how long it takes to
    /// look settled, and how much it overshoots. Bounce 0 is critically damped; negative is
    /// overdamped.
    public init(duration: Double, bounce: Double) {
        response = duration
        dampingFraction = bounce >= 0 ? 1 - bounce : 1 / (1 + bounce)
    }

    public var bounce: Double { dampingFraction <= 1 ? 1 - dampingFraction : 1 / dampingFraction - 1 }

    /// Slower or quicker for the speed setting; the bounce stays the same.
    public func scaled(_ factor: Double) -> SpringSpec {
        SpringSpec(response: response * factor, dampingFraction: dampingFraction)
    }

    /// Physical form for `interpolatingSpring(mass: 1, stiffness:, damping:)`.
    public var stiffness: Double { pow(2 * .pi / response, 2) }
    public var damping: Double { 4 * .pi * dampingFraction / response }
}

/// Whether the surface is getting bigger or smaller, which picks its spring. Closing to a live
/// pill shrinks just like closing to the bare notch, so it must not get the opening bounce.
public enum SurfaceMove: Sendable, Equatable {
    case grow
    case shrink

    /// By area, so a shape that gets wider but much shorter still settles without a bounce. No
    /// change in size counts as settling.
    public static func between(_ old: CGSize, _ new: CGSize) -> SurfaceMove {
        new.width * new.height > old.width * old.height ? .grow : .shrink
    }
}

/// Wisp's motion, after Apple's own (WWDC23 "Animate with springs"): springs described by
/// duration and bounce, bounce 0 for nearly everything, and a small bounce only where
/// something grows open, like the Dynamic Island swelling. Anything that tucks away, moves
/// between forms or follows the pointer settles without overshooting, so it reads as one
/// motion rather than a stretch and a second spring back. The timing is the same on every
/// display, whatever its refresh rate.
public enum SpringTuning {
    /// The shell growing (peek, activity or open): Apple's "snappy".
    public static let surfaceOpen = SpringSpec(duration: 0.42, bounce: 0.15)
    /// The shell shrinking, to a pill or back to closed: a little quicker, no overshoot.
    public static let surfaceClose = SpringSpec(duration: 0.36, bounce: 0)
    /// The shell travelling to a new form (notch, island, orb): one glide, no overshoot.
    public static let formMorph = SpringSpec(duration: 0.45, bounce: 0)
    /// Reduce Motion: short and critically damped, no overshoot.
    public static let reducedMotion = SpringSpec(duration: 0.3, bounce: 0)
    /// Content showing inside the growing shell: no delay, so it's carried by the shell rather
    /// than popping in after it.
    public static let contentIn = SpringSpec(duration: 0.3, bounce: 0)
    /// Content clearing, quicker than the shell so the shell is seen folding away empty.
    public static let contentOut = SpringSpec(duration: 0.16, bounce: 0)
    /// Hover, press and selection feedback.
    public static let control = SpringSpec(duration: 0.25, bounce: 0)
    /// Small surfaces appearing (the ring, the dock, bubbles): a hint of life as they open.
    public static let popover = SpringSpec(duration: 0.3, bounce: 0.1)

    public static func surface(move: SurfaceMove, speedScale: Double, reduceMotion: Bool) -> SpringSpec {
        if reduceMotion { return reducedMotion }
        return (move == .grow ? surfaceOpen : surfaceClose).scaled(speedScale)
    }
}
