import Foundation

/// Where the accent colour comes from. Settings shows it as one picker over the two stored
/// switches, `wallpaperTint` and `adaptiveAccent`.
public enum AccentSource: String, CaseIterable, Identifiable, Sendable {
    case theme
    case wallpaper
    case album

    public var id: Self { self }
    public var title: String {
        switch self {
        case .theme: "Theme"
        case .wallpaper: "Desktop picture"
        case .album: "Playing album"
        }
    }
}

extension Appearance {
    /// The album colour wins whenever it's on, as it always has. Both switches on (possible
    /// before the picker) reads as Playing album, falling back to the desktop picture; picking
    /// Playing album again leaves that as it is.
    public var accentSource: AccentSource {
        get {
            if adaptiveAccent { return .album }
            return wallpaperTint ? .wallpaper : .theme
        }
        set {
            switch newValue {
            case .theme:
                wallpaperTint = false
                adaptiveAccent = false
            case .wallpaper:
                wallpaperTint = true
                adaptiveAccent = false
            case .album:
                guard !adaptiveAccent else { return }
                wallpaperTint = false
                adaptiveAccent = true
            }
        }
    }

    /// What the accent follows under Playing album while nothing plays.
    public var albumFallback: AccentSource { wallpaperTint ? .wallpaper : .theme }

    /// One switch for confetti at every moment. On when any moment is on, so a choice made
    /// before the single switch keeps working until the switch is changed.
    public var confetti: Bool {
        get { confettiPomodoro || confettiAgent || confettiBattery }
        set {
            confettiPomodoro = newValue
            confettiAgent = newValue
            confettiBattery = newValue
        }
    }

    /// Some moments on and others off, from before the single switch.
    public var confettiIsPartial: Bool { confetti && !(confettiPomodoro && confettiAgent && confettiBattery) }
}
