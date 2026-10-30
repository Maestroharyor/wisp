import SwiftUI
import WispCore

/// Timing for the notch morph. The open content expands out of the notch with the
/// surface, both on one spring, so shell and content move as one; closing reverses it
/// into the notch. The nav pill settles in after.
struct NotchMotion {
    /// Surface spring when growing (peek, activity or open).
    let surfaceOpen: Animation
    /// Surface spring when shrinking back to closed.
    let surfaceClose: Animation
    /// Content condensing in after the surface has started opening.
    let contentIn: Animation
    /// Content dissipating, before the surface closes.
    let contentOut: Animation
    /// Nav pill settling in, after the content.
    let navIn: Animation
    /// Blur radius content condenses from.
    let contentBlur: CGFloat
    /// How far below its place compact content starts before drifting up.
    let contentDrift: CGFloat
    /// Whether open content scales from the notch width (off for Reduce Motion).
    let expands: Bool

    static func preset(_ speed: AnimationSpeed, framesPerSecond: Int, reduceMotion: Bool) -> NotchMotion {
        let open = SpringTuning.surface(
            opening: true, speedScale: speed.scale, framesPerSecond: framesPerSecond, reduceMotion: reduceMotion)
        let close = SpringTuning.surface(
            opening: false, speedScale: speed.scale, framesPerSecond: framesPerSecond, reduceMotion: reduceMotion)
        if reduceMotion {
            return NotchMotion(
                surfaceOpen: open.animation,
                surfaceClose: close.animation,
                contentIn: .easeInOut(duration: 0.2),
                contentOut: .easeOut(duration: 0.1),
                navIn: .easeInOut(duration: 0.2),
                contentBlur: 0,
                contentDrift: 0,
                expands: false
            )
        }
        let delay = 0.07 * speed.scale
        return NotchMotion(
            surfaceOpen: open.animation,
            surfaceClose: close.animation,
            contentIn: .spring(response: 0.46 * speed.scale, dampingFraction: 0.9).delay(delay),
            contentOut: .easeOut(duration: 0.14 * speed.scale),
            navIn: .spring(response: 0.42 * speed.scale, dampingFraction: 0.85).delay(delay + 0.08),
            contentBlur: 8,
            contentDrift: 10,
            expands: true
        )
    }
}

extension AnimationSpeed {
    /// Multiplier on spring responses and delays.
    var scale: Double {
        switch self {
        case .relaxed: 1.2
        case .standard: 1
        case .fast: 0.75
        }
    }
}

extension SpringSpec {
    var animation: Animation { .spring(response: response, dampingFraction: dampingFraction) }
}

/// Blur, fade, scale from the top and a vertical drift.
private struct MistModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    var offsetY: CGFloat = 0
    var offsetX: CGFloat = 0
    var scale = CGSize(width: 1, height: 1)

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(x: scale.width, y: scale.height, anchor: .top)
            .opacity(opacity)
            .offset(x: offsetX, y: offsetY)
    }
}

extension AnyTransition {
    /// Open content unfolds out of the notch with the surface: laid out at its final size,
    /// squeezed to the notch's width and height from the top, and driven by the same spring
    /// as the shell, so shell and content grow down and out as one. Closing folds it back
    /// up into the notch on the close spring. It starts part-visible so the growth reads.
    static func expand(_ motion: NotchMotion, fromScale: CGSize) -> AnyTransition {
        let start = motion.expands ? fromScale : CGSize(width: 1, height: 1)
        let collapsed = MistModifier(blur: motion.contentBlur / 2, opacity: motion.expands ? 0.35 : 0, scale: start)
        let open = MistModifier(blur: 0, opacity: 1)
        return .asymmetric(
            insertion: .modifier(active: collapsed, identity: open).animation(motion.surfaceOpen),
            removal: .modifier(active: collapsed, identity: open).animation(motion.surfaceClose)
        )
    }

    /// Switching shelf pages: the new page slides in from the side of its tab and the old
    /// one slides out the other way, both fading, while the shell resizes between them.
    static func pageSlide(_ motion: NotchMotion, forward: Bool) -> AnyTransition {
        let distance: CGFloat = motion.expands ? 36 : 0
        let incoming = MistModifier(blur: motion.contentBlur / 2, opacity: 0, offsetX: forward ? distance : -distance)
        let outgoing = MistModifier(blur: motion.contentBlur / 2, opacity: 0, offsetX: forward ? -distance : distance)
        let shown = MistModifier(blur: 0, opacity: 1)
        return .asymmetric(
            insertion: .modifier(active: incoming, identity: shown),
            removal: .modifier(active: outgoing, identity: shown).animation(motion.contentOut)
        )
    }

    /// Compact wings: the same motion, smaller, out of the camera housing.
    static func wingReveal(_ motion: NotchMotion) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: MistModifier(blur: motion.contentBlur / 2, opacity: 0, offsetY: motion.contentDrift / 3),
                identity: MistModifier(blur: 0, opacity: 1)
            )
            .animation(motion.contentIn),
            removal: .opacity.animation(motion.contentOut)
        )
    }

    /// Nav pill drifts down from under the shelf after the content settles. On close it
    /// rides up with the surface's bottom edge (`rideDistance`) and fades into the notch.
    static func navDrop(_ motion: NotchMotion, rideDistance: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: MistModifier(blur: 6, opacity: 0, offsetY: -12),
                identity: MistModifier(blur: 0, opacity: 1)
            )
            .animation(motion.navIn),
            removal: .modifier(
                active: MistModifier(blur: 4, opacity: 0, offsetY: -rideDistance),
                identity: MistModifier(blur: 0, opacity: 1)
            )
            .animation(motion.surfaceClose)
        )
    }
}
