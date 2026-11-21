import CoreGraphics
import Foundation

/// What VoiceOver says for Wisp's glanceable pills and cards: one short sentence each, so a
/// pill reads as a whole rather than as a symbol and a number.
public enum AccessibilityText {
    /// "6 minutes 41 seconds", "1 hour 2 minutes": the two largest units, in words.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(unit(hours, "hour")) }
        if minutes > 0 { parts.append(unit(minutes, "minute")) }
        if secs > 0, hours == 0 { parts.append(unit(secs, "second")) }
        return parts.isEmpty ? "0 seconds" : parts.prefix(2).joined(separator: " ")
    }

    public static func timer(label: String, remaining: TimeInterval) -> String {
        "\(label.isEmpty ? "Timer" : label), \(duration(remaining)) left"
    }

    public static func battery(percent: Int, charging: Bool, low: Bool) -> String {
        var text = "Battery \(percent)%"
        if charging { text += ", charging" }
        if low { text += ", low" }
        return text
    }

    public static func level(name: String, value: Double, muted: Bool) -> String {
        muted ? "\(name) muted" : "\(name) \(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    /// "Claude Code in wisp, working, 23% context". `warning` says the context is running low,
    /// which the pill otherwise shows only by colour.
    public static func agent(
        name: String, project: String?, state: String, context: Double?, warning: Bool = false
    ) -> String {
        var text = name
        if let project, !project.isEmpty { text += " in \(project)" }
        text += ", \(state.lowercased())"
        if let context { text += ", \(Int((context * 100).rounded()))% context" }
        if warning { text += ", running low" }
        return text
    }

    private static func unit(_ count: Int, _ name: String) -> String {
        "\(count) \(name)\(count == 1 ? "" : "s")"
    }
}

/// Legibility rules that follow the system's accessibility settings.
public enum ContrastStyle {
    /// Secondary text over the black notch: stronger with Increase Contrast.
    public static func secondaryOpacity(increased: Bool) -> Double { increased ? 0.8 : 0.55 }

    /// The smallest click target, in points, whatever the size of the glyph inside it.
    public static let minimumTarget: CGFloat = 24
}
