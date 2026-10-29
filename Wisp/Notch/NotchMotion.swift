import SwiftUI
import WispCore

/// Timing for the notch morph. Opening is layered: the surface springs open first,
/// then the content reveals (blur, scale and fade) slightly later, then the nav pill
/// drops in. Closing clears content first, then the surface settles back.
struct NotchMotion {
    /// Surface spring when growing (peek, activity or open).
    let surfaceOpen: Animation
    /// Surface spring when shrinking back to closed.
    let surfaceClose: Animation
    /// Content reveal after the surface has started opening.
    let contentIn: Animation
    /// Content hide, before the surface closes.
    let contentOut: Animation
    /// Nav pill drop-in, after the content.
    let navIn: Animation
    /// Blur radius content starts from when revealing.
    let contentBlur: CGFloat
    /// Scale content starts from when revealing.
    let contentScale: CGFloat

    /// Surface springs come from `SpringTuning` (measured reference values, stretched on
    /// low refresh rates). Content timing and the speed scales are our own.
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
                contentScale: 1
            )
        }
        let delay = 0.08 * speed.scale
        return NotchMotion(
            surfaceOpen: open.animation,
            surfaceClose: close.animation,
            contentIn: .spring(response: 0.34 * speed.scale, dampingFraction: 0.9).delay(delay),
            contentOut: .easeOut(duration: 0.11 * speed.scale),
            navIn: .spring(response: 0.36 * speed.scale, dampingFraction: 0.78).delay(delay + 0.05),
            contentBlur: 8,
            contentScale: 0.94
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

/// Blur + scale + fade, anchored to the top so content appears to drop out of the notch.
private struct RevealModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double
    var offsetY: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    /// The open content grows out of the notch with the surface: laid out at its final
    /// size, scaled from the notch width and driven by the same spring as the shell, so
    /// shell and content move as one (the reference drives both from one reveal clock).
    /// Closing reverses it on the close spring.
    static func notchEnlarge(_ motion: NotchMotion, fromScale: CGFloat) -> AnyTransition {
        let start = motion.contentScale < 1 ? fromScale : 1
        return .asymmetric(
            insertion: .modifier(
                active: RevealModifier(blur: motion.contentBlur / 2, scale: start, opacity: 0),
                identity: RevealModifier(blur: 0, scale: 1, opacity: 1)
            )
            .animation(motion.surfaceOpen),
            removal: .modifier(
                active: RevealModifier(blur: motion.contentBlur / 2, scale: start, opacity: 0),
                identity: RevealModifier(blur: 0, scale: 1, opacity: 1)
            )
            .animation(motion.surfaceClose)
        )
    }

    /// Compact wings: fade and un-blur out of the camera housing.
    static func wingReveal(_ motion: NotchMotion) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: RevealModifier(blur: motion.contentBlur / 2, scale: 0.8, opacity: 0),
                identity: RevealModifier(blur: 0, scale: 1, opacity: 1)
            )
            .animation(motion.contentIn),
            removal: .opacity.animation(motion.contentOut)
        )
    }

    /// Nav pill drops from under the shelf after the content settles. On close it rides
    /// up with the surface's bottom edge (`rideDistance`) and fades into the notch.
    static func navDrop(_ motion: NotchMotion, rideDistance: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: RevealModifier(blur: 4, scale: 0.9, opacity: 0, offsetY: -14),
                identity: RevealModifier(blur: 0, scale: 1, opacity: 1)
            )
            .animation(motion.navIn),
            removal: .modifier(
                active: RevealModifier(blur: 3, scale: 0.7, opacity: 0, offsetY: -rideDistance),
                identity: RevealModifier(blur: 0, scale: 1, opacity: 1)
            )
            .animation(motion.surfaceClose)
        )
    }
}
