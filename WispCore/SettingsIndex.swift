import Foundation

/// Every pane in Settings, in sidebar order.
public enum SettingsPaneID: String, CaseIterable, Sendable, Identifiable {
    case general
    case notch
    case appearance
    case activities
    /// Widgets, Clipboard and Profiles in one pane. It keeps the Widgets pane's stored value.
    case shelf = "widgets"
    case notifications
    /// Agents, with phone alerts folded in from the Phone pane.
    case agents
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
        case .shelf: "Shelf"
        case .notifications: "Notifications"
        case .agents: "Agents"
        case .ai: "AI"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    public var subtitle: String {
        switch self {
        case .general: "Shortcuts, dictation and startup"
        case .notch: "Where the notch sits, how it opens, and the ring"
        case .appearance: "Theme, shape, motion and the fun extras"
        case .activities: "What shows beside the notch while it's closed"
        case .shelf: "Widgets, clipboard history and profiles"
        case .notifications: "Notifications in the notch, and quick replies"
        case .agents: "Claude Code, Codex, Gemini CLI, Copilot CLI, Cursor and OpenCode, alerts and phone alerts"
        case .ai: "On-device AI with Apple Intelligence or Ollama"
        case .permissions: "What Wisp can access, and why"
        case .about: "Version, updates, diagnostics and reset"
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
                // The keyboard shortcuts list, which was in About. No "approve": it would pull
                // "app" searches here.
                "keyboard shortcuts", "shortcuts", "keyboard", "hyper y", "hyper n",
                "switch profile", "allow or deny", "pick an answer", "esc", "escape",
                "right-click the notch", "right click", "menu",
            ]
        case .notch:
            [
                "hover", "click", "open", "delay", "stay open", "auto close", "swipe", "gesture", "trackpad",
                "hidden", "drop actions", "command", "script", "island", "external", "display", "pocket", "drag",
                "shake", "position", "placement", "bottom", "left", "right", "corner", "edge", "side", "dock",
                "orb", "float", "detach", "move", "form", "shape", "window", "open as window", "windowed",
                "minimise", "minimize", "tear off", "normal app", "displays without a notch", "floating island",
                "don't show", "external displays", "show on external displays", "sidebar",
                // The ring, which had its own pane before; its name stays a keyword.
                "ring", "radial", "pie", "wheel", "mouse button", "middle click", "actions", "segments", "hyper r",
                "per app", "edit ring", "ring shortcut", "capture text", "ocr", "qr code", "barcode", "ai action",
                "quick add",
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
                "accessories", "low battery warning", "app volume", "per-app volume", "per app volume", "mixer",
                "up next", "queue", "next tracks", "playlist", "system audio recording",
                // Current control names, then the older ones so searches for those still land. Focus
                // changes moved here from Notifications, whose name stays a keyword.
                "use wisp for these pop-ups", "pop-ups", "popups", "show more than one activity at once",
                "more than one activity", "focus changes", "battery warning level", "batteries",
                "replace system overlays", "system overlays", "split extra activities", "show focus changes",
                "notifications",
            ]
        case .shelf:
            [
                // Widgets, Clipboard and Profiles had their own panes; their names stay keywords.
                "widgets", "home", "now playing", "calendar", "timer", "pomodoro", "weather", "notes",
                "toggles", "shortcuts", "clipboard", "mirror", "camera", "day progress", "world clocks", "cities",
                "timer length", "command output", "command", "output", "run every", "script", "do not disturb",
                "dnd", "workday", "focus button runs this shortcut", "focus button", "do not disturb toggle runs",
                "clipboard history", "history", "copy", "paste", "limit", "keep up to", "pinned", "clear history",
                "concealed", "passwords", "ocr", "text from image", "working hours", "time zone",
                "profiles", "profile", "context", "automatic", "rules", "work", "music", "meeting", "code", "focus",
                "save current setup", "switch profiles automatically", "switch automatically", "opens on",
                "profile look", "look for", "keep the current look", "quick add", "quick input", "reminder",
                "reminders", "event", "natural language",
            ]
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
                "history", "session history", "past sessions", "summary", "summaries", "clear history",
                "keep session history", "summarise finished sessions", "summarize finished sessions",
                "alerts", "estimated spend today", "last 7 days",
                "warn", "warn at", "critical", "critical at", "context colour", "context color", "context ring",
                "compact now", "approval history", "approvals", "spend cap", "pause at", "per session", "keep going",
                "edit rule", "sounds", "agent sounds", "mute", "mute during calls or focus", "needs approval",
                "finished", "failed", "context warning", "context critical", "choose file", "chime",
                // Phone alerts, which had their own pane; its name stays a keyword.
                "phone", "phone alerts", "send agent alerts to my phone", "ntfy", "push", "iphone", "android",
                "apple watch", "watch", "mobile", "remote", "away", "idle", "locked", "topic", "qr", "send test",
                "what to send",
            ]
        case .ai:
            [
                "apple intelligence", "foundation models", "ollama", "llm", "language model", "on-device", "local",
                "localhost", "summarise", "summarize", "translate", "grammar", "rewrite", "action items", "explain",
                "try it", "translate to", "language", "selection", "selected text", "clipboard actions", "replace",
            ]
        case .permissions:
            [
                "accessibility", "full disk", "screen recording", "contacts", "automation", "calendars", "camera",
                "microphone", "speech recognition", "reminders",
            ]
        case .about:
            [
                "version", "github", "issue", "reset", "help", "updates", "sparkle", "release", "check for updates",
                "check now", "website", "run setup again", "reset all settings",
                // Copy diagnostics took over Notch's Copy display info; that name stays a keyword.
                "copy diagnostics", "diagnostics", "bug report", "copy display info", "display info",
            ]
        }
    }

    /// Words for the controls under this pane's Advanced disclosure. Searching for them, or
    /// for "advanced", finds the pane, and any search opens the disclosure.
    public var advancedKeywords: [String] {
        switch self {
        case .general:
            ["show wisp in the menu bar", "menu bar icon", "caps lock on its own", "quick press", "turns caps lock on"]
        case .notch:
            [
                "dynamic island detection", "dynamic island", "camera", "hole punch", "displays", "each display",
                "per display", "move back", "reset position",
                "this mac has a dynamic island",
            ]
        case .appearance: ["glow reach", "reach", "spread", "pointer effect", "hover strength", "strength"]
        case .activities:
            [
                "volume steps", "steps", "finer", "pop-ups stay on screen", "level bars",
                "theme accent", "teams", "google meet", "chromium", "first bubble", "show on",
                "display under the pointer", "macbook display", "all displays",
            ]
        case .shelf:
            ["widget rows", "rows", "grid", "one row", "two rows", "clipboard keeps up to", "history length"]
        case .agents:
            [
                // Current control names, then the older ones so searches for those still land.
                "status line under claude code's prompt", "status line", "keep mine",
                "show what agents are doing", "command-line tool", "wisp command",
                "your own ntfy server", "server", "self-hosted", "access token", "reply token",
                "add the command or file name", "away after", "wait for an answer", "approval timeout",
                "terminal bar", "claude code status bar", "tool activity", "show tool activity", "protected server",
                "include details", "agent sound volume", "volume",
            ]
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
        case "clipboard", "profiles": return .shelf
        case "phone": return .agents
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
    case features
    case system

    public var id: Self { self }

    public var title: String {
        switch self {
        case .wisp: "Wisp"
        case .features: "Features"
        case .system: "System"
        }
    }

    public var panes: [SettingsPaneID] {
        switch self {
        case .wisp: [.general, .notch, .appearance]
        case .features: [.activities, .shelf, .notifications, .agents, .ai]
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
