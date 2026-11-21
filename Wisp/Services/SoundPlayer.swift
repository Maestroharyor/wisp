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
        if event.isInterface {
            let source = SoundPack.interfaceSound(
                for: event, enabled: look.interfaceSounds, pack: look.soundPack, custom: look.customSounds)
            if let source { play(source) }
            return
        }
        if let source = SoundPack.sound(for: event, pack: look.soundPack, custom: look.customSounds) {
            play(source)
        } else if let fallback {
            play(.system(fallback))
        }
    }

    /// The macOS sounds in /System/Library/Sounds by name, for the agent sound pickers.
    static let systemSounds: [String] = {
        let folder = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }()

    /// An agent moment's sound, at the agent sound volume.
    func play(_ source: SoundSource, volume: Double) {
        play(source, gain: Float(volume))
    }

    func play(_ source: SoundSource) {
        play(source, gain: 1)
    }

    /// Settings' play button: the event's sound even while its switch is off, so it can be heard
    /// before choosing.
    func preview(_ event: SoundEvent) {
        let look = preferences.appearance
        let pack = event.isInterface && look.soundPack == .off ? .soft : look.soundPack
        if let source = SoundPack.sound(for: event, pack: pack, custom: look.customSounds) { play(source) }
    }

    private func play(_ source: SoundSource, gain: Float) {
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
        sound.volume = gain
        sound.play()
    }
}
