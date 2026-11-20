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

/// Notch surface timing, after Apple's own: growing carries a small bounce, like the Dynamic
/// Island swelling open; shrinking is a little quicker and critically damped, so it tucks
/// away without wobbling. The timing is the same on every display, whatever its refresh rate.
public enum SpringTuning {
    public static let surfaceOpen = SpringSpec(response: 0.42, dampingFraction: 0.8)
    public static let surfaceClose = SpringSpec(response: 0.36, dampingFraction: 1)
    /// Reduce Motion: short and critically damped, no overshoot.
    public static let reducedMotion = SpringSpec(response: 0.3, dampingFraction: 1)
    /// Content showing inside the growing shell: no delay, so it's carried by the shell rather
    /// than popping in after it.
    public static let contentIn = SpringSpec(response: 0.3, dampingFraction: 1)
    /// Content clearing, quicker than the shell so the shell is seen folding away empty.
    public static let contentOut = SpringSpec(response: 0.16, dampingFraction: 1)

    public static func surface(move: SurfaceMove, speedScale: Double, reduceMotion: Bool) -> SpringSpec {
        if reduceMotion { return reducedMotion }
        let base = move == .grow ? surfaceOpen : surfaceClose
        return SpringSpec(response: base.response * speedScale, dampingFraction: base.dampingFraction)
    }
}
