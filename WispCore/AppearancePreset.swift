import Foundation

/// A named look. Built-ins ship with Wisp; people can save their own.
public struct AppearancePreset: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var appearance: Appearance

    public var id: String { name }

    public init(name: String, appearance: Appearance) {
        self.name = name
        self.appearance = appearance
    }

    public static let builtIns: [AppearancePreset] = [
        AppearancePreset(name: "Default", appearance: .standard),
        AppearancePreset(name: "Calm", appearance: calm),
        AppearancePreset(name: "Arcade", appearance: arcade),
        AppearancePreset(name: "Minimal", appearance: minimal),
        AppearancePreset(name: "Neon", appearance: neon),
    ]

    public static func isBuiltIn(_ name: String) -> Bool { builtIns.contains { $0.name == name } }

    /// A name that clashes with neither a built-in nor a saved preset.
    public static func uniqueName(_ name: String, existing: [String]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "My look" : trimmed
        let taken = Set(existing + builtIns.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private static var calm: Appearance {
        var look = Appearance.standard
        look.theme = .midnight
        look.animationSpeed = .relaxed
        look.roundness = 1.2
        look.glassEdge = .strong
        look.glowIntensity = 0.6
        look.breathingGlow = true
        look.hoverFeedback = .glow
        look.timeOfDay = .sunset
        look.soundPack = .soft
        return look
    }

    private static var arcade: Appearance {
        var look = Appearance.standard
        look.theme = .ember
        look.animationSpeed = .fast
        look.hoverFeedback = .wobble
        look.hoverStrength = 1.4
        look.glowIntensity = 1.4
        look.musicGlow = true
        look.confettiPomodoro = true
        look.confettiAgent = true
        look.confettiBattery = true
        look.pet = true
        look.soundPack = .classic
        return look
    }

    private static var minimal: Appearance {
        var look = Appearance.standard
        look.theme = .mono
        look.minimalPill = true
        look.navPill = .dots
        look.shadow = .none
        look.glowIntensity = 0.3
        look.hoverFeedback = .none
        look.roundness = 0.8
        look.valueFont = .system
        return look
    }

    private static var neon: Appearance {
        var look = Appearance.standard
        look.theme = .aurora
        look.surface = .tinted
        look.outline = .bold
        look.shimmer = true
        look.glowIntensity = 1.6
        look.glowSpread = 1.3
        look.grain = .light
        look.musicGlow = true
        look.valueFont = .monospaced
        return look
    }
}

/// A `.wisplook` file: one named look, shared between Macs.
public struct LookFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let fileExtension = "wisplook"

    public var version: Int
    public var name: String
    public var appearance: Appearance

    /// Custom sounds are paths on this Mac (and reveal its user name), so they stay behind.
    public init(name: String, appearance: Appearance) {
        version = Self.currentVersion
        self.name = name
        var shared = appearance
        shared.customSounds = [:]
        if shared.soundPack == .custom { shared.soundPack = .off }
        self.appearance = shared
    }

    public enum ReadError: Error, Equatable {
        case notALook
        case newerVersion(Int)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads a look file. Values are clamped on the way in; a file from a newer Wisp is refused.
    public static func decode(_ data: Data) throws(ReadError) -> LookFile {
        guard let file = try? JSONDecoder().decode(LookFile.self, from: data) else { throw ReadError.notALook }
        guard file.version >= 1 else { throw ReadError.notALook }
        guard file.version <= currentVersion else { throw ReadError.newerVersion(file.version) }
        return file
    }
}
