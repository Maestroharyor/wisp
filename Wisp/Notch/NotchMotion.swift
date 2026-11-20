import SwiftUI
import WispCore

/// Timing for the notch morph. The black shell grows out of the notch on a spring and the
/// content comes with it from the first frame, on short springs that never overshoot, so the
/// two read as one motion; closing, the content clears quickly and the shell folds back into
/// the notch. Springs only, so any of it can be interrupted and turn around smoothly.
struct NotchMotion {
    /// Surface spring when growing (peek, activity or open).
    let surfaceOpen: Animation
    /// Surface spring when shrinking, to a pill or back to closed.
    let surfaceClose: Animation
    /// Shelf content arriving with the growing shell.
    let shelfIn: Animation
    /// Content dissipating, before the surface closes.
    let contentOut: Animation
    /// Nav pill settling in, after the content.
    let navIn: Animation
    /// Compact activity content arriving with the shell.
    let wingIn: Animation
    /// Compact activity content clearing, ahead of the shell retracting over it.
    let wingOut: Animation
    /// How much content scales up as it arrives (it starts at this share of its size).
    let contentScale: CGFloat
    /// Off for Reduce Motion: no drift, scale or slide.
    let expands: Bool

    static func preset(_ speed: AnimationSpeed, reduceMotion: Bool) -> NotchMotion {
        let open = SpringTuning.surface(move: .grow, speedScale: speed.scale, reduceMotion: reduceMotion)
        let close = SpringTuning.surface(move: .shrink, speedScale: speed.scale, reduceMotion: reduceMotion)
        if reduceMotion {
            return NotchMotion(
                surfaceOpen: open.animation,
                surfaceClose: close.animation,
                shelfIn: .easeInOut(duration: 0.2),
                contentOut: .easeOut(duration: 0.1),
                navIn: .easeInOut(duration: 0.2),
                wingIn: .easeInOut(duration: 0.2),
                wingOut: .easeOut(duration: 0.1),
                contentScale: 1,
                expands: false
            )
        }
        let contentIn = SpringTuning.contentIn.scaled(speed.scale).animation
        let contentOut = SpringTuning.contentOut.scaled(speed.scale).animation
        return NotchMotion(
            surfaceOpen: open.animation,
            surfaceClose: close.animation,
            shelfIn: contentIn,
            contentOut: contentOut,
            // Chrome under the shelf, so it may trail the shell by a beat.
            navIn: .spring(response: 0.36 * speed.scale, dampingFraction: 0.86).delay(0.05 * speed.scale),
            wingIn: contentIn,
            wingOut: contentOut,
            contentScale: 0.94,
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

    func scaled(_ factor: Double) -> SpringSpec {
        SpringSpec(response: response * factor, dampingFraction: dampingFraction)
    }
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
    /// Open content grows out of the notch with the shell: scaled down a little from the top
    /// edge and clear, then full size inside the shell's clip. Closing, it clears quickly so
    /// the shell is seen folding back into the notch.
    static func unfold(_ motion: NotchMotion) -> AnyTransition {
        let scale = CGSize(width: motion.contentScale, height: motion.contentScale)
        let hidden = MistModifier(blur: 0, opacity: 0, scale: scale)
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
        let incoming = MistModifier(blur: 0, opacity: 0, offsetX: forward ? distance : -distance)
        let outgoing = MistModifier(blur: 0, opacity: 0, offsetX: forward ? -distance : distance)
        let shown = MistModifier(blur: 0, opacity: 1)
        return .asymmetric(
            insertion: .modifier(active: incoming, identity: shown),
            removal: .modifier(active: outgoing, identity: shown).animation(motion.contentOut)
        )
    }

    /// Compact wings, as on the shell: the content spreads out from the camera with the shell
    /// (scaled about the centre, so both wings move outward) and contracts toward it on the
    /// way out, clearing before the shell retracts over it.
    static func wingReveal(_ motion: NotchMotion) -> AnyTransition {
        let scale = motion.expands ? CGSize(width: 0.8, height: 0.8) : CGSize(width: 1, height: 1)
        let hidden = MistModifier(blur: 0, opacity: 0, scale: scale, anchor: .center)
        let shown = MistModifier(blur: 0, opacity: 1, anchor: .center)
        return .asymmetric(
            insertion: .modifier(active: hidden, identity: shown).animation(motion.wingIn),
            removal: .modifier(active: hidden, identity: shown).animation(motion.wingOut)
        )
    }

    /// Content from the floating orb: it grows out of the orb (`anchor`, where the orb sits in
    /// the surface) from a blur, and condenses back into it. Pills use the quicker wing timing.
    static func bloom(_ motion: NotchMotion, from anchor: UnitPoint, pill: Bool) -> AnyTransition {
        let scale = motion.expands ? CGSize(width: 0.82, height: 0.82) : CGSize(width: 1, height: 1)
        let hidden = MistModifier(blur: motion.expands ? 3 : 0, opacity: 0, scale: scale, anchor: anchor)
        let shown = MistModifier(blur: 0, opacity: 1, anchor: anchor)
        return .asymmetric(
            insertion: .modifier(active: hidden, identity: shown).animation(pill ? motion.wingIn : motion.shelfIn),
            removal: .modifier(active: hidden, identity: shown).animation(pill ? motion.wingOut : motion.contentOut)
        )
    }

    /// Nav pill drifts out from under the shelf (`drift`) after the content settles. On close
    /// it rides back with the surface (`ride`) and fades into the notch.
    /// With Reduce Motion it only fades in place.
    static func navDrop(_ motion: NotchMotion, ride: CGSize, drift: CGSize) -> AnyTransition {
        let drift = motion.expands ? drift : .zero
        let ride = motion.expands ? ride : .zero
        return .asymmetric(
            insertion: .modifier(
                active: MistModifier(blur: 0, opacity: 0, offsetY: drift.height, offsetX: drift.width),
                identity: MistModifier(blur: 0, opacity: 1)
            )
            .animation(motion.navIn),
            removal: .modifier(
                active: MistModifier(blur: 0, opacity: 0, offsetY: ride.height, offsetX: ride.width),
                identity: MistModifier(blur: 0, opacity: 1)
            )
            .animation(motion.surfaceClose)
        )
    }
}
