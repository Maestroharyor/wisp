import Foundation

/// Every pane in Settings, in sidebar order.
public enum SettingsPaneID: String, CaseIterable, Sendable, Identifiable {
    case general
    case notch
    case appearance
    case activities
    case widgets
    case profiles
    case clipboard
    case notifications
    case agents
    case phone
    case ai
    case permissions
    case about

    public var id: Self { self }

    public var title: String {
        switch self {
        case .general: "General"
        case .notch: "Notch"
        case .appearance: "Appearance"
        case .activities: "Live Activities"
        case .widgets: "Widgets"
        case .profiles: "Profiles"
        case .clipboard: "Clipboard"
        case .notifications: "Notifications"
        case .agents: "Agents"
        case .phone: "Phone"
        case .ai: "AI"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    public var subtitle: String {
        switch self {
        case .general: "Shortcuts, startup and setup"
        case .notch: "Where the notch sits, how it opens, and the ring"
        case .appearance: "Theme, shape, motion and the fun extras"
        case .activities: "What shows beside the notch while it's closed"
        case .widgets: "The widgets on Home and the Widgets page"
        case .profiles: "Saved setups, and switching them automatically"
        case .clipboard: "Clipboard history"
        case .notifications: "Notifications in the notch, and quick replies"
        case .agents:
            "Claude Code, Codex, Gemini CLI, Copilot CLI, Cursor and OpenCode sessions, approvals and status bar"
        case .phone: "Agent alerts and approvals on your phone and watch"
        case .ai: "On-device AI with Apple Intelligence or Ollama"
        case .permissions: "What Wisp can access, and why"
        case .about: "Version, updates, shortcuts and reset"
        }
    }

    /// Words people might type to find this pane, beyond its title.
    var keywords: [String] {
        switch self {
        case .general:
            [
                "shortcut", "hotkey", "caps lock", "hyper", "space", "launch", "login", "startup", "accessibility",
                "menu bar", "icon", "dictation", "dictate", "speech", "speech recognition", "voice", "push to talk",
                "transcribe", "speak", "microphone",
            ]
        case .notch:
            [
                "hover", "click", "open", "delay", "stay open", "auto close", "swipe", "gesture", "trackpad",
                "hidden", "drop actions", "command", "script", "island", "external", "display", "pocket", "drag",
                "shake", "position", "placement", "bottom", "left", "right", "corner", "edge", "side", "dock",
                "orb", "float", "detach", "move", "form", "shape", "window", "open as window", "windowed",
                "minimise", "minimize", "tear off", "normal app", "displays without a notch", "floating island",
                "don't show", "external displays", "show on external displays",
                // The ring, which had its own pane before; its name stays a keyword.
                "ring", "radial", "pie", "wheel", "mouse button", "middle click", "actions", "segments", "hyper r",
                "per app", "edit ring", "ring shortcut",
            ]
        case .appearance:
            [
                "look", "theme", "glass", "surface", "tinted", "black", "accent", "album", "colour", "color",
                "gradient", "aurora", "midnight", "ember", "mono", "wallpaper", "desktop picture", "outline",
                "animation", "speed", "preset", "mood", "calm", "arcade", "minimal", "neon", "roundness", "radius",
                "corners", "shadow", "opacity", "transparent", "size", "compact", "roomy", "glow", "grain",
                "shimmer", "nav", "pill", "dots", "font", "type", "hover", "wobble", "ears", "idle", "time",
                "date", "breathing", "music glow", "beat", "sunset", "night", "light", "dark", "sound", "sound pack",
                "confetti", "celebrate", "pet", "sprite", "import", "export", "share", "reset",
                // Current control names, then the older ones so searches for those still land.
                "shape", "effects", "edge highlight", "number style", "accent follows", "playing album",
                "change colour through the day", "change color through the day", "beside the closed notch",
                "sounds", "shell", "finish", "glass edge", "numbers in", "through the day", "while idle",
                "match the desktop picture", "tint with the playing album",
            ]
        case .activities:
            [
                "volume", "brightness", "battery", "hud", "overlay", "media", "music", "pointer", "display", "focus",
                "lyrics", "lrclib", "album art", "artwork", "itunes", "lock screen", "meeting", "call", "microphone",
                "recording",
                "zoom", "meet", "teams", "mute", "camera", "leave", "call controls", "bubbles", "split",
                "duration", "low battery", "threshold",
                "left", "right", "airpods", "headphones", "bluetooth", "downloads", "download progress", "safari",
                "chrome", "firefox", "folder", "finder", "mouse", "keyboard", "trackpad", "magic mouse", "accessory",
                "accessories", "low battery warning",
                // Current control names, then the older ones so searches for those still land. Focus
                // changes moved here from Notifications, whose name stays a keyword.
                "use wisp for these pop-ups", "pop-ups", "popups", "show more than one activity at once",
                "more than one activity", "focus changes", "battery warning level", "batteries",
                "replace system overlays", "system overlays", "split extra activities", "show focus changes",
                "notifications",
            ]
        case .widgets:
            [
                "home", "now playing", "calendar", "timer", "pomodoro", "weather", "notes",
                "toggles", "shortcuts", "clipboard", "mirror", "camera", "day progress", "world clocks", "cities",
                "timer length", "script", "command", "output", "do not disturb", "dnd", "workday",
                "focus button runs this shortcut", "focus button", "do not disturb toggle runs",
            ]
        case .profiles: ["profile", "context", "automatic", "rules", "work", "music", "meeting", "code", "focus"]
        case .clipboard: ["history", "copy", "paste", "limit", "pinned"]
        case .notifications:
            [
                "messages", "imessage", "whatsapp", "telegram", "reply", "banner", "apps", "dismiss",
                "close", "stay on screen", "duration", "swipe",
            ]
        case .agents:
            [
                "claude", "claude code", "codex", "gemini", "gemini cli", "copilot", "copilot cli", "github copilot",
                "cursor", "cursor-agent", "opencode", "open code", "plugin", "ai", "hooks", "approve", "allow", "deny",
                "sessions", "sound", "permission sound",
                "spend", "cost", "tokens", "status bar", "statusline", "context", "terminal", "compact", "privacy",
                "private", "hide", "call", "screen share", "transcript", "tool", "activity", "subagent", "pill",
                "command line", "cli", "wisp status", "path", "budget", "long-running", "reminder", "nudge",
                "usage limit", "rate limit", "weekly limit", "question", "answer", "preview", "diff", "plan",
                "keep awake", "sleep", "power", "rules", "always allow", "permission rule", "settings.local.json",
                "cloud", "cloud agents", "codex cloud", "copilot", "coding agent", "agent task", "github", "gh",
                "cursor", "background agent", "api key", "pull request", "pr", "ci", "checks", "codex apply",
                "tmux", "iterm", "ghostty", "wezterm", "jump to terminal", "tab", "pane", "keyboard",
            ]
        case .phone:
            [
                "ntfy", "push", "iphone", "android", "apple watch", "watch", "mobile", "remote", "away", "idle",
                "locked", "topic", "qr", "server", "self-hosted", "access token", "approval timeout", "test",
                "include details",
            ]
        case .ai:
            [
                "apple intelligence", "foundation models", "ollama", "llm", "language model", "on-device", "local",
                "localhost", "summarise", "summarize", "translate", "grammar", "rewrite", "action items", "explain",
                "try it",
            ]
        case .permissions:
            [
                "accessibility", "full disk", "screen recording", "contacts", "automation", "calendars", "camera",
                "microphone", "speech recognition",
            ]
        case .about:
            [
                "version", "github", "issue", "reset", "shortcuts", "help", "updates", "sparkle", "release", "keyboard",
                "approve with keyboard", "hyper y", "check for updates", "check now",
            ]
        }
    }

    /// Words for the controls under this pane's Advanced disclosure. Searching for them, or
    /// for "advanced", finds the pane, and any search opens the disclosure.
    public var advancedKeywords: [String] {
        switch self {
        case .notch:
            [
                "dynamic island detection", "dynamic island", "camera", "hole punch", "copy display info",
                "display info", "displays", "each display", "per display", "move back", "reset position",
                "this mac has a dynamic island",
            ]
        case .appearance: ["glow reach", "reach", "spread", "pointer effect", "hover strength", "strength"]
        case .activities:
            [
                "volume steps", "steps", "finer", "pop-ups stay on screen", "level bars",
                "theme accent", "teams", "google meet", "chromium", "first bubble", "show on",
                "display under the pointer", "macbook display", "all displays",
            ]
        case .widgets: ["widget rows", "rows", "grid", "one row", "two rows"]
        default: []
        }
    }

    /// The pane to show for a stored `lastSettingsPane` value. Panes that were folded into
    /// another open that one; anything unknown opens General.
    public static func restoring(_ rawValue: String?) -> SettingsPaneID {
        guard let rawValue else { return .general }
        if let pane = SettingsPaneID(rawValue: rawValue) { return pane }
        switch rawValue {
        case "ring": return .notch
        default: return .general
        }
    }

    /// Everything a search looks through for this pane besides its title.
    var searchTerms: [String] {
        advancedKeywords.isEmpty ? keywords : keywords + ["advanced"] + advancedKeywords
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
        case .wisp: [.general, .notch, .appearance, .activities]
        case .shelf: [.widgets, .profiles, .clipboard]
        case .connections: [.notifications, .agents, .phone, .ai]
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
            !byTitle.contains($0) && matches(([$0.title] + $0.searchTerms).joined(separator: " "))
        }
        return byTitle + byKeyword
    }

    /// Apostrophes are dropped, straight or curly, so "dont show" finds "don't show".
    private static func normalise(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
