import SwiftUI
import WispCore

/// Timing for the notch morph. The black shell grows out of the notch on a spring and
/// uncovers the content as it goes; closing, the content clears and the shell shrinks
/// back into the notch. The nav pill settles in after.
struct NotchMotion {
    /// Surface spring when growing (peek, activity or open).
    let surfaceOpen: Animation
    /// Surface spring when shrinking back to closed.
    let surfaceClose: Animation
    /// Shelf content fading in once the shell has mostly grown, so nothing shows while
    /// the box is still small and cutting it off.
    let shelfIn: Animation
    /// Content dissipating, before the surface closes.
    let contentOut: Animation
    /// Nav pill settling in, after the content.
    let navIn: Animation
    /// Compact activity content resolving once the shell has mostly grown.
    let wingIn: Animation
    /// Compact activity content clearing. The close spring starts from rest, so this
    /// finishes while the shell has only begun to retract.
    let wingOut: Animation
    /// Blur radius content condenses from.
    let contentBlur: CGFloat
    /// Off for Reduce Motion: no drift, scale or slide.
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
                shelfIn: .easeInOut(duration: 0.2),
                contentOut: .easeOut(duration: 0.1),
                navIn: .easeInOut(duration: 0.2),
                wingIn: .easeInOut(duration: 0.2),
                wingOut: .easeOut(duration: 0.1),
                contentBlur: 0,
                expands: false
            )
        }
        let delay = 0.07 * speed.scale
        return NotchMotion(
            surfaceOpen: open.animation,
            surfaceClose: close.animation,
            shelfIn: .easeOut(duration: 0.18 * speed.scale).delay(0.24 * speed.scale),
            contentOut: .easeOut(duration: 0.14 * speed.scale),
            navIn: .spring(response: 0.42 * speed.scale, dampingFraction: 0.85).delay(delay + 0.08),
            wingIn: .spring(response: 0.36 * speed.scale, dampingFraction: 0.86).delay(0.12 * speed.scale),
            wingOut: .easeOut(duration: 0.12 * speed.scale),
            contentBlur: 8,
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
    var anchor = UnitPoint.top

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(x: scale.width, y: scale.height, anchor: anchor)
            .opacity(opacity)
            .offset(x: offsetX, y: offsetY)
    }
}

extension AnyTransition {
    /// Open content as with CSS `overflow: hidden`: laid out at its final size inside the
    /// growing black shell, and faded in once the shell is most of the way open.
    /// Closing, it clears quickly so the shell is seen shrinking back into the notch.
    static func unfold(_ motion: NotchMotion) -> AnyTransition {
        let hidden = MistModifier(blur: motion.contentBlur / 2, opacity: 0)
        let shown = MistModifier(blur: 0, opacity: 1)
        return .asymmetric(
            insertion: .modifier(active: hidden, identity: shown).animation(motion.shelfIn),
            removal: .modifier(active: hidden, identity: shown).animation(motion.contentOut)
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

    /// Compact wings, as on the shell: the black leads and the content resolves out of a blur
    /// once the shell has mostly grown, drawn in from the camera (scaled about the centre, so
    /// both wings spread outward). On the way out it contracts toward the camera and clears
    /// before the shell retracts over it.
    static func wingReveal(_ motion: NotchMotion) -> AnyTransition {
        let scale = motion.expands ? CGSize(width: 0.6, height: 0.6) : CGSize(width: 1, height: 1)
        let hidden = MistModifier(blur: motion.expands ? 6 : 0, opacity: 0, scale: scale, anchor: .center)
        let shown = MistModifier(blur: 0, opacity: 1, anchor: .center)
        return .asymmetric(
            insertion: .modifier(active: hidden, identity: shown).animation(motion.wingIn),
            removal: .modifier(active: hidden, identity: shown).animation(motion.wingOut)
        )
    }

    /// Nav pill drifts out from under the shelf (`drift`) after the content settles. On close
    /// it rides back with the surface (`ride`) and fades into the notch.
    static func navDrop(_ motion: NotchMotion, ride: CGSize, drift: CGSize) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: MistModifier(blur: 6, opacity: 0, offsetY: drift.height, offsetX: drift.width),
                identity: MistModifier(blur: 0, opacity: 1)
            )
            .animation(motion.navIn),
            removal: .modifier(
                active: MistModifier(blur: 4, opacity: 0, offsetY: ride.height, offsetX: ride.width),
                identity: MistModifier(blur: 0, opacity: 1)
            )
            .animation(motion.surfaceClose)
        )
    }
}
