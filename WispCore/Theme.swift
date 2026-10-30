import Foundation

/// An sRGB colour as plain numbers, so themes can be stored and tested without SwiftUI.
public struct RGB: Equatable, Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = RGB(red: 1, green: 1, blue: 1)

    /// "#7A6BFF" or "7a6bff"; nil for anything else.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    public var hex: String { ColorHex.string(red: red, green: green, blue: blue) }

    /// Brightens a sampled colour (wallpaper, album art) so it still glows on black,
    /// keeping its hue.
    public func liftedForGlow(minimum: Double = 0.75) -> RGB {
        let brightest = max(red, green, blue)
        guard brightest > 0 else { return RGB(red: minimum, green: minimum, blue: minimum) }
        guard brightest < minimum else { return self }
        let scale = minimum / brightest
        return RGB(red: red * scale, green: green * scale, blue: blue * scale)
    }
}

public enum ThemeID: String, CaseIterable, Sendable, Codable {
    case violet
    case midnight
    case aurora
    case ember
    case mono
    case custom

    public static let `default` = ThemeID.violet
}

/// The accent (selection, progress, active states) and the glow colour of the open
/// shelf. When they differ, the glow runs from one to the other.
public struct ThemePalette: Equatable, Sendable, Codable {
    public var accent: RGB
    public var glow: RGB

    public init(accent: RGB, glow: RGB) {
        self.accent = accent
        self.glow = glow
    }
}

public enum ThemeCatalog {
    private static func rgb(_ hex: String) -> RGB { RGB(hex: hex) ?? .white }

    public static let violet = rgb("#7A6BFF")
    public static let teal = rgb("#2EC4B6")

    public static func palette(for id: ThemeID, custom: ThemePalette) -> ThemePalette {
        switch id {
        case .violet: ThemePalette(accent: violet, glow: violet)
        case .midnight: ThemePalette(accent: rgb("#4C7DFF"), glow: rgb("#2541B2"))
        case .aurora: ThemePalette(accent: violet, glow: teal)
        case .ember: ThemePalette(accent: rgb("#FF7A45"), glow: rgb("#FF3D7F"))
        case .mono: ThemePalette(accent: rgb("#D9D9DE"), glow: rgb("#8E8E99"))
        case .custom: custom
        }
    }

    public static func title(for id: ThemeID) -> String {
        switch id {
        case .violet: "Wisp violet"
        case .midnight: "Midnight"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .mono: "Mono"
        case .custom: "Custom"
        }
    }
}
