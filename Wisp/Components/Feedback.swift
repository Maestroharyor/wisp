import AppKit
import WispCore

/// Small confirmations when something lands: a trackpad tap (Force Touch trackpads only, and
/// only while a finger is on it) and, with Interface sounds on, a quiet sound.
@MainActor
enum Feedback {
    /// Set once at launch, so views and services can confirm without passing the player around.
    static weak var sounds: SoundPlayer?

    /// A selection moved to something new, such as the next app on the ring.
    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Something settled into place: a dragged icon, a shelf height, a switch.
    static func landed() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Files landed on a drop target.
    static func dropped() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        sounds?.play(.drop)
    }

    static func copied() {
        sounds?.play(.copy)
    }

    /// An agent's request was allowed or denied.
    static func decided() {
        sounds?.play(.decision)
    }
}
