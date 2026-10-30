import Foundation

// MARK: Sounds

public enum SoundPackID: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case soft
    case classic
    case custom

    public var id: Self { self }
    public var title: String {
        switch self {
        case .off: "Off"
        case .soft: "Soft"
        case .classic: "Classic"
        case .custom: "My sounds"
        }
    }
}

public enum SoundEvent: String, CaseIterable, Identifiable, Sendable, Codable {
    case open
    case close
    case done
    case alert

    public var id: Self { self }
    public var title: String {
        switch self {
        case .open: "Shelf opens"
        case .close: "Shelf closes"
        case .done: "Something finishes"
        case .alert: "Something needs you"
        }
    }
}

public enum SoundSource: Equatable, Sendable {
    /// A sound in /System/Library/Sounds, by name.
    case system(String)
    /// An audio file the user picked.
    case file(String)
}

public enum SoundPack {
    /// The sound for an event, or nil for silence.
    public static func sound(for event: SoundEvent, pack: SoundPackID, custom: [String: String]) -> SoundSource? {
        switch pack {
        case .off: nil
        case .soft: .system(soft(event))
        case .classic: .system(classic(event))
        case .custom: custom[event.rawValue].flatMap { $0.isEmpty ? nil : .file($0) }
        }
    }

    private static func soft(_ event: SoundEvent) -> String {
        switch event {
        case .open: "Tink"
        case .close: "Pop"
        case .done: "Purr"
        case .alert: "Ping"
        }
    }

    private static func classic(_ event: SoundEvent) -> String {
        switch event {
        case .open: "Morse"
        case .close: "Bottle"
        case .done: "Glass"
        case .alert: "Hero"
        }
    }
}

// MARK: Time of day

public enum TimeOfDayTint {
    static let warm = RGB(red: 1, green: 0.62, blue: 0.35)
    static let cool = RGB(red: 0.35, green: 0.55, blue: 1)
    /// How far the accent moves toward warm or cool at most.
    static let strength = 0.4

    /// The accent for this minute of the day (0 to 1439).
    public static func tint(_ base: RGB, minuteOfDay: Int, mode: TimeOfDayMode, isDark: Bool) -> RGB {
        switch mode {
        case .off:
            return base
        case .lightDark:
            return isDark ? base : mix(base, .white, 0.2)
        case .sunset:
            let (warmth, coolness) = weights(minuteOfDay: minuteOfDay)
            return mix(mix(base, warm, warmth * strength), cool, coolness * strength)
        }
    }

    /// Warmth peaks 18:30 to 19:30; coolness holds from 23:00 to 04:00.
    static func weights(minuteOfDay: Int) -> (warm: Double, cool: Double) {
        let minute = Double(((minuteOfDay % 1440) + 1440) % 1440)
        let warm = ramp(minute, rise: (17 * 60, 18.5 * 60), fall: (19.5 * 60, 21 * 60))
        let lateNight = ramp(minute, rise: (21.5 * 60, 23 * 60), fall: (1440, 1441))
        let earlyMorning = ramp(minute, rise: (-1, 0), fall: (4 * 60, 5.5 * 60))
        return (warm, max(lateNight, earlyMorning))
    }

    private static func ramp(_ x: Double, rise: (Double, Double), fall: (Double, Double)) -> Double {
        if x < rise.0 || x >= fall.1 { return 0 }
        if x < rise.1 { return (x - rise.0) / (rise.1 - rise.0) }
        if x < fall.0 { return 1 }
        return 1 - (x - fall.0) / (fall.1 - fall.0)
    }

    static func mix(_ a: RGB, _ b: RGB, _ amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(
            red: a.red + (b.red - a.red) * t,
            green: a.green + (b.green - a.green) * t,
            blue: a.blue + (b.blue - a.blue) * t)
    }
}

// MARK: Glow pulse

public enum GlowPulse {
    public enum Mode: Sendable {
        case off
        /// A slow in-and-out, one breath every four seconds.
        case breathing
        /// A simulated 120 bpm beat with a stronger first beat in each bar.
        case beat
    }

    public static let breathPeriod = 4.0
    public static let beatsPerSecond = 2.0

    /// Glow level from 0 to 1 at `time` seconds.
    public static func level(time: Double, mode: Mode) -> Double {
        switch mode {
        case .off:
            return 0
        case .breathing:
            return 0.5 - 0.5 * cos(2 * .pi * time / breathPeriod)
        case .beat:
            let beats = max(time, 0) * beatsPerSecond
            let phase = beats - beats.rounded(.down)
            let accent = Int(beats.rounded(.down)) % 4 == 0 ? 1 : 0.6
            return exp(-phase * 6) * accent
        }
    }
}

// MARK: Idle ears

public struct EarContext: Sendable {
    public var now: Date
    public var calendar: Calendar
    public var uses24Hour: Bool
    public var batteryLevel: Int?
    public var nextMeeting: Date?
    public var weather: String?
    public var customText: String

    public init(
        now: Date, calendar: Calendar = .current, uses24Hour: Bool = false, batteryLevel: Int? = nil,
        nextMeeting: Date? = nil, weather: String? = nil, customText: String = ""
    ) {
        self.now = now
        self.calendar = calendar
        self.uses24Hour = uses24Hour
        self.batteryLevel = batteryLevel
        self.nextMeeting = nextMeeting
        self.weather = weather
        self.customText = customText
    }
}

public enum IdleEars {
    /// Text for one ear, or nil when the slot is off or has nothing to say.
    public static func text(for slot: EarSlot, context: EarContext) -> String? {
        let text: String? =
            switch slot {
            case .off: nil
            case .time: time(context)
            case .date: date(context)
            case .battery: context.batteryLevel.map { "\(min(max($0, 0), 100))%" }
            case .meeting: meeting(context)
            case .weather: context.weather
            case .custom: context.customText.trimmingCharacters(in: .whitespaces)
            }
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(Appearance.earTextLimit))
    }

    private static func time(_ context: EarContext) -> String {
        let parts = context.calendar.dateComponents([.hour, .minute], from: context.now)
        let hour = parts.hour ?? 0
        let minute = String(format: "%02d", parts.minute ?? 0)
        if context.uses24Hour { return "\(hour):\(minute)" }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve):\(minute)"
    }

    private static func date(_ context: EarContext) -> String {
        let parts = context.calendar.dateComponents([.weekday, .day], from: context.now)
        let symbols = context.calendar.shortWeekdaySymbols
        let index = (parts.weekday ?? 1) - 1
        let weekday = symbols.indices.contains(index) ? symbols[index] : ""
        return "\(weekday) \(parts.day ?? 1)"
    }

    /// "now" once it has started (for 10 minutes), "in 12m" within the hour, "in 3h" later today.
    private static func meeting(_ context: EarContext) -> String? {
        guard let start = context.nextMeeting else { return nil }
        let minutes = Int((start.timeIntervalSince(context.now) / 60).rounded(.up))
        switch minutes {
        case ..<(-10): return nil
        case ...0: return "now"
        case ..<60: return "in \(minutes)m"
        case ..<(12 * 60): return "in \(minutes / 60)h"
        default: return nil
        }
    }
}

// MARK: Celebrations

public enum CelebrationEvent: Equatable, Sendable {
    case pomodoroDone
    case agentDone(duration: TimeInterval)
    case batteryFull
}

public enum Celebration {
    /// An agent run counts as long once it passes five minutes.
    public static let longAgentRun: TimeInterval = 5 * 60

    public static func shouldFire(_ event: CelebrationEvent, look: Appearance) -> Bool {
        switch event {
        case .pomodoroDone: look.confettiPomodoro
        case .agentDone(let duration): look.confettiAgent && duration >= longAgentRun
        case .batteryFull: look.confettiBattery
        }
    }
}

// MARK: Pet

public enum PetMood: String, Sendable {
    case asleep
    case awake
    case alert
    case happy

    /// The pet dozes off after two quiet minutes.
    public static let sleepAfter: TimeInterval = 120

    public static func mood(needsAttention: Bool, celebrating: Bool, idleFor: TimeInterval) -> PetMood {
        if celebrating { return .happy }
        if needsAttention { return .alert }
        return idleFor >= sleepAfter ? .asleep : .awake
    }
}
