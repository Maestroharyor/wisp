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
