import Foundation

/// Every pane in Settings, in sidebar order.
public enum SettingsPaneID: String, CaseIterable, Sendable, Identifiable {
    case general
    case notch
    case activities
    case widgets
    case profiles
    case clipboard
    case notifications
    case agents
    case permissions
    case about

    public var id: Self { self }

    public var title: String {
        switch self {
        case .general: "General"
        case .notch: "Notch & Look"
        case .activities: "Live Activities"
        case .widgets: "Widgets"
        case .profiles: "Profiles"
        case .clipboard: "Clipboard"
        case .notifications: "Notifications"
        case .agents: "Agents"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    public var subtitle: String {
        switch self {
        case .general: "Shortcuts, startup and setup"
        case .notch: "How the notch opens and what it looks like"
        case .activities: "What shows beside the notch while it's closed"
        case .widgets: "The widgets on Home and the Widgets page"
        case .profiles: "Saved setups, and switching them automatically"
        case .clipboard: "Clipboard history"
        case .notifications: "Notifications in the notch, and quick replies"
        case .agents: "Claude Code sessions and approvals"
        case .permissions: "What Wisp can access, and why"
        case .about: "Version, shortcuts and reset"
        }
    }

    /// Words people might type to find this pane, beyond its title.
    var keywords: [String] {
        switch self {
        case .general:
            ["shortcut", "hotkey", "caps lock", "hyper", "space", "launch", "login", "startup", "accessibility"]
        case .notch:
            [
                "hover", "click", "open", "delay", "glass", "surface", "tinted", "black", "accent", "album",
                "animation", "speed", "island", "external", "display", "pocket", "drag", "shake",
            ]
        case .activities:
            ["volume", "brightness", "battery", "hud", "overlay", "media", "music", "pointer", "display", "focus"]
        case .widgets:
            [
                "home", "grid", "rows", "now playing", "calendar", "timer", "pomodoro", "weather", "notes",
                "toggles", "shortcuts", "clipboard", "mirror", "camera", "day progress", "world clocks", "cities",
            ]
        case .profiles: ["profile", "context", "automatic", "rules", "work", "music", "meeting", "code", "focus"]
        case .clipboard: ["history", "copy", "paste", "limit", "pinned"]
        case .notifications: ["messages", "imessage", "whatsapp", "telegram", "reply", "banner", "apps", "focus"]
        case .agents: ["claude", "claude code", "codex", "ai", "hooks", "approve", "allow", "deny", "sessions"]
        case .permissions:
            ["accessibility", "full disk", "screen recording", "contacts", "automation", "calendars", "camera"]
        case .about: ["version", "github", "issue", "reset", "shortcuts", "help"]
        }
    }
}

public enum SettingsSection: String, CaseIterable, Sendable, Identifiable {
    case wisp
    case shelf
    case connections
    case system

    public var id: Self { self }

    public var title: String {
        switch self {
        case .wisp: "Wisp"
        case .shelf: "Shelf"
        case .connections: "Connections"
        case .system: "System"
        }
    }

    public var panes: [SettingsPaneID] {
        switch self {
        case .wisp: [.general, .notch, .activities]
        case .shelf: [.widgets, .profiles, .clipboard]
        case .connections: [.notifications, .agents]
        case .system: [.permissions, .about]
        }
    }
}

/// Search for the Settings sidebar.
public enum SettingsIndex {
    /// Panes whose title or keywords contain every word of `query`: panes matching by
    /// title first, then by keyword, each in sidebar order.
    public static func panes(matching query: String) -> [SettingsPaneID] {
        let words = normalise(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return SettingsPaneID.allCases }
        func matches(_ text: String) -> Bool { words.allSatisfy(normalise(text).contains) }
        let byTitle = SettingsPaneID.allCases.filter { matches($0.title) }
        let byKeyword = SettingsPaneID.allCases.filter {
            !byTitle.contains($0) && matches(([$0.title] + $0.keywords).joined(separator: " "))
        }
        return byTitle + byKeyword
    }

    private static func normalise(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
