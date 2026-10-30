import AppKit
import WispCore

/// Plays the chosen sound pack's sound for each moment. Events keep their old sound
/// (passed as `fallback`) when the pack has none for them, so timers never go silent.
@MainActor
final class SoundPlayer {
    private let preferences: Preferences
    /// Loaded sounds by name or path, so repeats don't reread the file.
    private var cache: [String: NSSound] = [:]

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func play(_ event: SoundEvent, fallback: String? = nil) {
        let look = preferences.appearance
        if let source = SoundPack.sound(for: event, pack: look.soundPack, custom: look.customSounds) {
            play(source)
        } else if let fallback {
            play(.system(fallback))
        }
    }

    func play(_ source: SoundSource) {
        let key: String
        let sound: NSSound?
        switch source {
        case .system(let name):
            key = name
            sound = cache[key] ?? NSSound(named: name)
        case .file(let path):
            key = path
            sound = cache[key] ?? NSSound(contentsOfFile: path, byReference: true)
        }
        guard let sound else { return }
        cache[key] = sound
        sound.stop()
        sound.play()
    }
}
