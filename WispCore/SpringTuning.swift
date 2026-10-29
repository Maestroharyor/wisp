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

/// Notch surface timing. Values measured from the reference app's motion presets
/// (see droppy-analysis/features/animation.md); the scaling rules are ours to tune.
public enum SpringTuning {
    public static let surfaceOpen = SpringSpec(response: 0.47, dampingFraction: 0.76)
    public static let surfaceClose = SpringSpec(response: 0.54, dampingFraction: 0.9)
    /// Reduce Motion: short and critically damped, no overshoot.
    public static let reducedMotion = SpringSpec(response: 0.3, dampingFraction: 1)

    /// Low refresh rates show fewer frames per spring, so stretch the response a little
    /// to keep the motion from looking choppy.
    public static func refreshScale(framesPerSecond: Int) -> Double {
        switch framesPerSecond {
        case 100...: 1
        case 75..<100: 1.1
        default: 1.18
        }
    }

    public static func surface(
        opening: Bool,
        speedScale: Double,
        framesPerSecond: Int,
        reduceMotion: Bool
    ) -> SpringSpec {
        let refresh = refreshScale(framesPerSecond: framesPerSecond)
        if reduceMotion {
            return SpringSpec(response: reducedMotion.response * refresh, dampingFraction: 1)
        }
        let base = opening ? surfaceOpen : surfaceClose
        return SpringSpec(response: base.response * speedScale * refresh, dampingFraction: base.dampingFraction)
    }
}
