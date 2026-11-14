import Foundation

/// The moments an agent can make a sound for, each with its own switch and sound in
/// Settings › Agents › Sounds.
public enum AgentSoundEvent: String, CaseIterable, Codable, Identifiable, Sendable {
    case needsApproval
    case question
    case finished
    /// The agent quit without ending its session (a crash or a closed terminal).
    case failed
    case contextWarning
    case contextCritical
    case spendCap
    /// A usage window passed the alert level or 95%.
    case limitWarning
    /// A usage window was used up.
    case limitReached
    /// A usage window that had passed the alert level started over.
    case limitReset

    public var id: Self { self }

    public var title: String {
        switch self {
        case .needsApproval: "Needs approval"
        case .question: "Question"
        case .finished: "Finished"
        case .failed: "Failed"
        case .contextWarning: "Context warning"
        case .contextCritical: "Context critical"
        case .spendCap: "Spend cap"
        case .limitWarning: "Limit warning"
        case .limitReached: "Limit reached"
        case .limitReset: "Limit reset"
        }
    }

    /// The macOS sound it starts with. Requests keep the chime they had before sounds per event.
    var defaultSetting: AgentSoundSetting {
        switch self {
        case .needsApproval, .question: AgentSoundSetting(on: true, sound: .system("Tink"))
        case .finished: AgentSoundSetting(on: false, sound: .system("Glass"))
        case .failed: AgentSoundSetting(on: false, sound: .system("Basso"))
        case .contextWarning: AgentSoundSetting(on: false, sound: .system("Purr"))
        case .contextCritical: AgentSoundSetting(on: false, sound: .system("Sosumi"))
        case .spendCap: AgentSoundSetting(on: true, sound: .system("Funk"))
        case .limitWarning: AgentSoundSetting(on: false, sound: .system("Bottle"))
        case .limitReached: AgentSoundSetting(on: true, sound: .system("Submarine"))
        case .limitReset: AgentSoundSetting(on: false, sound: .system("Hero"))
        }
    }
}

public struct AgentSoundSetting: Codable, Equatable, Sendable {
    public var on: Bool
    /// A sound in /System/Library/Sounds, or an audio file the user picked (its path).
    public var sound: SoundSource

    public init(on: Bool, sound: SoundSource) {
        self.on = on
        self.sound = sound
    }
}

/// Every agent sound setting, saved as one JSON value. Events missing from a saved value (one
/// added later) keep their defaults.
public struct AgentSounds: Codable, Equatable, Sendable {
    private var events: [String: AgentSoundSetting] = [:]
    private var storedVolume: Double = 1
    /// Agent sounds stay quiet while the microphone is in a call or a Focus is on.
    public var muteDuringCallsOrFocus = true

    public init() {}

    public subscript(event: AgentSoundEvent) -> AgentSoundSetting {
        get { events[event.rawValue] ?? event.defaultSetting }
        set { events[event.rawValue] = newValue }
    }

    /// 0 to 1, applied on top of the Mac's volume.
    public var volume: Double {
        get { storedVolume }
        set { storedVolume = min(max(newValue, 0), 1) }
    }

    private enum CodingKeys: String, CodingKey {
        case events, volume, muteDuringCallsOrFocus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = (try? container.decode([String: AgentSoundSetting].self, forKey: .events)) ?? [:]
        volume = (try? container.decode(Double.self, forKey: .volume)) ?? 1
        muteDuringCallsOrFocus = (try? container.decode(Bool.self, forKey: .muteDuringCallsOrFocus)) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(storedVolume, forKey: .volume)
        try container.encode(muteDuringCallsOrFocus, forKey: .muteDuringCallsOrFocus)
    }

    /// The settings for someone upgrading: the old "Play a sound when an agent asks for
    /// permission" switch (nil when never set) turns the request sounds on or off, and a sound
    /// pack that was on carries its alert sound to requests and its done sound to Finished,
    /// which it used to play.
    public static func migrated(approvalSound: Bool?, pack: SoundPackID, custom: [String: String]) -> AgentSounds {
        var sounds = AgentSounds()
        if let alert = SoundPack.sound(for: .alert, pack: pack, custom: custom) {
            sounds[.needsApproval].sound = alert
            sounds[.question].sound = alert
        }
        if let done = SoundPack.sound(for: .done, pack: pack, custom: custom) {
            sounds[.finished] = AgentSoundSetting(on: true, sound: done)
        }
        if let approvalSound {
            sounds[.needsApproval].on = approvalSound
            sounds[.question].on = approvalSound
        }
        return sounds
    }
}

/// Picks the sound for an agent moment, and plays each event at most once per session within
/// `burstWindow`, so a burst of requests chimes once.
public struct SoundRule: Sendable {
    public static let burstWindow: TimeInterval = 3

    private var lastPlayed: [String: Date] = [:]

    public init() {}

    /// The sound to play now, or nil: the event is off, muted, or chimed a moment ago.
    /// `muted` is a call or Focus being on.
    public mutating func sound(
        for event: AgentSoundEvent, session: String?, settings: AgentSounds, muted: Bool, now: Date
    ) -> SoundSource? {
        let setting = settings[event]
        guard setting.on, !(muted && settings.muteDuringCallsOrFocus) else { return nil }
        let key = event.rawValue + "|" + (session ?? "")
        if let last = lastPlayed[key], now.timeIntervalSince(last) < Self.burstWindow { return nil }
        lastPlayed = lastPlayed.filter { now.timeIntervalSince($0.value) < Self.burstWindow }
        lastPlayed[key] = now
        return setting.sound
    }
}
