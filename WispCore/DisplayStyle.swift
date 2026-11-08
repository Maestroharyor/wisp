import Foundation

/// How Wisp appears on one display. `automatic` follows the external-display settings.
public enum DisplayStyle: String, CaseIterable, Sendable {
    case automatic
    case notch
    case island
    case hidden

    public static func resolve(
        _ choice: DisplayStyle, hasNotch: Bool, showOnExternal: Bool, externalIsland: Bool,
        systemIsland: Bool = false
    ) -> DisplayStyle {
        guard choice == .automatic else { return choice }
        // A hole-punch camera may still report a housing; drawing a notch there covers Apple's island.
        if systemIsland { return .island }
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

/// What Settings shows as "On displays without a notch". It's one picker over the two stored
/// settings, show on external displays and the external style.
public enum NotchlessDisplayChoice: String, CaseIterable, Identifiable, Sendable {
    case notch
    case island
    case hidden

    public var id: Self { self }
    public var title: String {
        switch self {
        case .notch: "Notch"
        case .island: "Floating island"
        case .hidden: "Don't show"
        }
    }

    public init(showOnExternal: Bool, externalIsland: Bool) {
        if !showOnExternal {
            self = .hidden
        } else {
            self = externalIsland ? .island : .notch
        }
    }

    /// The stored settings for this choice. Don't show keeps the current style, so picking
    /// Notch or Floating island later is the only thing that changes it.
    public func stored(externalIsland current: Bool) -> (showOnExternal: Bool, externalIsland: Bool) {
        switch self {
        case .notch: (true, false)
        case .island: (true, true)
        case .hidden: (false, current)
        }
    }
}
