import Foundation

/// Overall speed of the notch morph.
public enum AnimationSpeed: String, CaseIterable, Identifiable, Sendable, Codable {
    case relaxed
    case standard
    case fast

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
}

/// What the open surface is made of. The closed notch is always black so it
/// blends with the camera housing.
public enum SurfaceStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case black
    case glass
    case tinted

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
}

/// Translucent fade at the bottom edge of the open surface.
public enum GlassEdge: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case subtle
    case strong

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    /// Opacity of black left at the very bottom edge.
    public var bottomOpacity: Double {
        switch self {
        case .off: 1
        case .subtle: 0.72
        case .strong: 0.45
        }
    }
}

/// How the accent shifts through the day.
public enum TimeOfDayMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    /// Warmer around sunset, cooler late at night.
    case sunset
    /// Brighter in Light Mode, deeper in Dark Mode.
    case lightDark

    public var id: Self { self }
    public var title: String {
        switch self {
        case .off: "Off"
        case .sunset: "Warm at sunset, cool at night"
        case .lightDark: "Follow Light and Dark"
        }
    }
}

public enum ShellShadow: String, CaseIterable, Identifiable, Sendable, Codable {
    case none
    case soft
    case deep

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    /// Opacity and blur of the open shell's shadow.
    public var opacity: Double {
        switch self {
        case .none: 0
        case .soft: 0.5
        case .deep: 0.75
        }
    }
    public var radius: Double {
        switch self {
        case .none: 0
        case .soft: 18
        case .deep: 28
        }
    }
}

public enum ShelfSize: String, CaseIterable, Identifiable, Sendable, Codable {
    case compact
    case standard
    case roomy

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    /// Multiplier on shelf widths.
    public var scale: CGFloat {
        switch self {
        case .compact: 0.9
        case .standard: 1
        case .roomy: 1.12
        }
    }
}

public enum GrainLevel: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case light
    case heavy

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    public var opacity: Double {
        switch self {
        case .off: 0
        case .light: 0.05
        case .heavy: 0.11
        }
    }
}

public enum OutlineWidth: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case thin
    case bold

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
    public var lineWidth: CGFloat {
        switch self {
        case .off: 0
        case .thin: 1
        case .bold: 2
        }
    }
}

public enum NavPillStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case pill
    case dots
    case hidden

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
}

/// Type used for countdowns, percentages and clocks.
public enum ValueFont: String, CaseIterable, Identifiable, Sendable, Codable {
    case system
    case rounded
    case monospaced
    case serif

    public var id: Self { self }
    public var title: String { rawValue.capitalized }
}

/// What the closed notch does when the pointer reaches it.
public enum HoverFeedback: String, CaseIterable, Identifiable, Sendable, Codable {
    case grow
    case glow
    case wobble
    case none

    public var id: Self { self }
    public var title: String {
        switch self {
        case .grow: "Grow"
        case .glow: "Glow"
        case .wobble: "Wobble"
        case .none: "Nothing"
        }
    }
}

/// Small text either side of the idle notch.
public enum EarSlot: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case time
    case date
    case battery
    case meeting
    case weather
    case custom

    public var id: Self { self }
    public var title: String {
        switch self {
        case .off: "Nothing"
        case .time: "Time"
        case .date: "Date"
        case .battery: "Battery"
        case .meeting: "Next meeting"
        case .weather: "Weather"
        case .custom: "My text"
        }
    }
}

/// Every look setting in one value, so presets, profiles and look files carry all of it.
/// Decoding never fails on a missing or unknown field: each falls back to its default and
/// numbers are clamped, so old files and newer fields both load.
public struct Appearance: Equatable, Sendable {
    // Theme
    public var theme: ThemeID = .default
    public var customAccent: RGB = ThemeCatalog.violet
    public var customGlow: RGB = ThemeCatalog.teal
    public var wallpaperTint = false
    public var adaptiveAccent = false
    public var timeOfDay: TimeOfDayMode = .off
    // Shell
    public var surface: SurfaceStyle = .black
    public var glassEdge: GlassEdge = .subtle
    /// Multiplier on every shell corner radius.
    public var roundness: Double = 1
    public var shadow: ShellShadow = .soft
    /// Opacity of the Black and Tinted surfaces.
    public var opacity: Double = 1
    public var shelfSize: ShelfSize = .standard
    // Finish
    public var glowIntensity: Double = 1
    public var glowSpread: Double = 1
    public var grain: GrainLevel = .off
    public var shimmer = false
    public var outline: OutlineWidth = .off
    public var navPill: NavPillStyle = .pill
    // Pills
    public var minimalPill = false
    public var valueFont: ValueFont = .rounded
    // Motion
    public var animationSpeed: AnimationSpeed = .standard
    public var hoverFeedback: HoverFeedback = .grow
    public var hoverStrength: Double = 1
    // Idle
    public var leftEar: EarSlot = .off
    public var rightEar: EarSlot = .off
    public var earText = ""
    public var breathingGlow = false
    public var musicGlow = false
    // Fun
    public var soundPack: SoundPackID = .off
    /// Audio file paths for the Custom pack, by `SoundEvent` raw value.
    public var customSounds: [String: String] = [:]
    public var confettiPomodoro = false
    public var confettiAgent = false
    public var confettiBattery = false
    public var pet = false

    public init() {}

    /// This look, keeping `current`'s custom sound files when it has none of its own.
    /// Built-in presets carry no files, so trying one must not throw away the user's.
    public func keepingSounds(of current: Appearance) -> Appearance {
        guard customSounds.isEmpty else { return self }
        var merged = self
        merged.customSounds = current.customSounds
        return merged
    }

    public static let standard = Appearance()

    public static let roundnessRange: ClosedRange<Double> = 0.5...1.5
    public static let opacityRange: ClosedRange<Double> = 0.7...1
    public static let glowRange: ClosedRange<Double> = 0...1.6
    public static let hoverStrengthRange: ClosedRange<Double> = 0...2
    public static let earTextLimit = 12

    /// The same look with every number and text inside its allowed range.
    public func clamped() -> Appearance {
        var copy = self
        copy.roundness = Self.clamp(roundness, Self.roundnessRange)
        copy.opacity = Self.clamp(opacity, Self.opacityRange)
        copy.glowIntensity = Self.clamp(glowIntensity, Self.glowRange)
        copy.glowSpread = Self.clamp(glowSpread, Self.glowRange)
        copy.hoverStrength = Self.clamp(hoverStrength, Self.hoverStrengthRange)
        copy.earText = String(earText.prefix(Self.earTextLimit))
        return copy
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 1
    }
}

extension Appearance: Codable {
    private enum CodingKeys: String, CodingKey {
        case theme, customAccent, customGlow, wallpaperTint, adaptiveAccent, timeOfDay
        case surface, glassEdge, roundness, shadow, opacity, shelfSize
        case glowIntensity, glowSpread, grain, shimmer, outline, navPill
        case minimalPill, valueFont
        case animationSpeed, hoverFeedback, hoverStrength
        case leftEar, rightEar, earText, breathingGlow, musicGlow
        case soundPack, customSounds, confettiPomodoro, confettiAgent, confettiBattery, pet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let base = Appearance.standard
        theme = read(.theme, base.theme)
        customAccent = read(.customAccent, base.customAccent)
        customGlow = read(.customGlow, base.customGlow)
        wallpaperTint = read(.wallpaperTint, base.wallpaperTint)
        adaptiveAccent = read(.adaptiveAccent, base.adaptiveAccent)
        timeOfDay = read(.timeOfDay, base.timeOfDay)
        surface = read(.surface, base.surface)
        glassEdge = read(.glassEdge, base.glassEdge)
        roundness = read(.roundness, base.roundness)
        shadow = read(.shadow, base.shadow)
        opacity = read(.opacity, base.opacity)
        shelfSize = read(.shelfSize, base.shelfSize)
        glowIntensity = read(.glowIntensity, base.glowIntensity)
        glowSpread = read(.glowSpread, base.glowSpread)
        grain = read(.grain, base.grain)
        shimmer = read(.shimmer, base.shimmer)
        outline = read(.outline, base.outline)
        navPill = read(.navPill, base.navPill)
        minimalPill = read(.minimalPill, base.minimalPill)
        valueFont = read(.valueFont, base.valueFont)
        animationSpeed = read(.animationSpeed, base.animationSpeed)
        hoverFeedback = read(.hoverFeedback, base.hoverFeedback)
        hoverStrength = read(.hoverStrength, base.hoverStrength)
        leftEar = read(.leftEar, base.leftEar)
        rightEar = read(.rightEar, base.rightEar)
        earText = read(.earText, base.earText)
        breathingGlow = read(.breathingGlow, base.breathingGlow)
        musicGlow = read(.musicGlow, base.musicGlow)
        soundPack = read(.soundPack, base.soundPack)
        customSounds = read(.customSounds, base.customSounds)
        confettiPomodoro = read(.confettiPomodoro, base.confettiPomodoro)
        confettiAgent = read(.confettiAgent, base.confettiAgent)
        confettiBattery = read(.confettiBattery, base.confettiBattery)
        pet = read(.pet, base.pet)
        self = clamped()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(customAccent, forKey: .customAccent)
        try container.encode(customGlow, forKey: .customGlow)
        try container.encode(wallpaperTint, forKey: .wallpaperTint)
        try container.encode(adaptiveAccent, forKey: .adaptiveAccent)
        try container.encode(timeOfDay, forKey: .timeOfDay)
        try container.encode(surface, forKey: .surface)
        try container.encode(glassEdge, forKey: .glassEdge)
        try container.encode(roundness, forKey: .roundness)
        try container.encode(shadow, forKey: .shadow)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(shelfSize, forKey: .shelfSize)
        try container.encode(glowIntensity, forKey: .glowIntensity)
        try container.encode(glowSpread, forKey: .glowSpread)
        try container.encode(grain, forKey: .grain)
        try container.encode(shimmer, forKey: .shimmer)
        try container.encode(outline, forKey: .outline)
        try container.encode(navPill, forKey: .navPill)
        try container.encode(minimalPill, forKey: .minimalPill)
        try container.encode(valueFont, forKey: .valueFont)
        try container.encode(animationSpeed, forKey: .animationSpeed)
        try container.encode(hoverFeedback, forKey: .hoverFeedback)
        try container.encode(hoverStrength, forKey: .hoverStrength)
        try container.encode(leftEar, forKey: .leftEar)
        try container.encode(rightEar, forKey: .rightEar)
        try container.encode(earText, forKey: .earText)
        try container.encode(breathingGlow, forKey: .breathingGlow)
        try container.encode(musicGlow, forKey: .musicGlow)
        try container.encode(soundPack, forKey: .soundPack)
        try container.encode(customSounds, forKey: .customSounds)
        try container.encode(confettiPomodoro, forKey: .confettiPomodoro)
        try container.encode(confettiAgent, forKey: .confettiAgent)
        try container.encode(confettiBattery, forKey: .confettiBattery)
        try container.encode(pet, forKey: .pet)
    }
}

/// The look settings earlier builds kept as separate preference keys.
public struct LegacyLook: Equatable, Sendable {
    public var theme: String?
    public var customAccent: String?
    public var customGlow: String?
    public var wallpaperTint = false
    public var adaptiveAccent = false
    public var shellOutline = false
    public var animationSpeed: String?
    public var surface: String?
    public var glassEdge: String?

    public init(
        theme: String? = nil, customAccent: String? = nil, customGlow: String? = nil, wallpaperTint: Bool = false,
        adaptiveAccent: Bool = false, shellOutline: Bool = false, animationSpeed: String? = nil,
        surface: String? = nil, glassEdge: String? = nil
    ) {
        self.theme = theme
        self.customAccent = customAccent
        self.customGlow = customGlow
        self.wallpaperTint = wallpaperTint
        self.adaptiveAccent = adaptiveAccent
        self.shellOutline = shellOutline
        self.animationSpeed = animationSpeed
        self.surface = surface
        self.glassEdge = glassEdge
    }
}

extension Appearance {
    /// Carries the old separate settings over, so an upgrade keeps the look exactly.
    public static func migrated(from legacy: LegacyLook) -> Appearance {
        var look = Appearance.standard
        look.theme = legacy.theme.flatMap(ThemeID.init(rawValue:)) ?? look.theme
        look.customAccent = legacy.customAccent.flatMap(RGB.init(hex:)) ?? look.customAccent
        look.customGlow = legacy.customGlow.flatMap(RGB.init(hex:)) ?? look.customGlow
        look.wallpaperTint = legacy.wallpaperTint
        look.adaptiveAccent = legacy.adaptiveAccent
        look.outline = legacy.shellOutline ? .thin : .off
        look.animationSpeed = legacy.animationSpeed.flatMap(AnimationSpeed.init(rawValue:)) ?? look.animationSpeed
        look.surface = legacy.surface.flatMap(SurfaceStyle.init(rawValue:)) ?? look.surface
        look.glassEdge = legacy.glassEdge.flatMap(GlassEdge.init(rawValue:)) ?? look.glassEdge
        return look
    }
}
