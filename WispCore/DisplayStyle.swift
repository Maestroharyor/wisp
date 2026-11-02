import Foundation

/// How Wisp appears on one display. `automatic` follows the external-display settings.
public enum DisplayStyle: String, CaseIterable, Sendable {
    case automatic
    case notch
    case island
    case hidden

    public static func resolve(
        _ choice: DisplayStyle, hasNotch: Bool, showOnExternal: Bool, externalIsland: Bool
    ) -> DisplayStyle {
        guard choice == .automatic else { return choice }
        if hasNotch { return .notch }
        guard showOnExternal else { return .hidden }
        return externalIsland ? .island : .notch
    }
}

/// What Settings calls a display. Some displays (AirPlay, a few adapters) report no name,
/// which left their row unlabelled; they're named by kind and size instead.
public enum DisplayName {
    public static func title(name: String, builtIn: Bool, width: Int, height: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return builtIn ? "Built-in display" : "External display (\(width) × \(height))"
    }
}
