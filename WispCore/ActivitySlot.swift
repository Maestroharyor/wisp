import Foundation

/// Where each live activity source posts, and the rules that decide how it competes for
/// the notch. Higher priority wins the main pill.
public enum ActivitySlot: String, CaseIterable, Sendable {
    case media
    case timer
    case tray
    case battery
    case notice
    case timerDone
    case notification
    case focus
    case capsLock
    case level
    case agent
    case agentApproval
    case meeting
    case meetingSoon
    case device
    case download
    case downloadDone
    /// Posted by a script, Shortcut or link (`wisp activity`, `wisp://activity`).
    case external
    case regionWatch
    case dictation

    /// Ongoing activities sit below every short alert, so a battery or device alert still
    /// shows during a call and then hands the pill back.
    public var priority: Int {
        switch self {
        case .media: 10
        case .agent: 15
        case .external: 17
        case .regionWatch: 18
        case .timer: 20
        case .download: 22
        case .meeting: 25
        case .tray: 30
        case .battery: 40
        case .device: 41
        case .focus: 42
        case .notice: 45
        case .timerDone: 46
        case .downloadDone: 47
        case .meetingSoon: 48
        case .notification: 50
        case .agentApproval: 55
        // Held down on purpose, so it shows over cards; only HUDs (volume, Caps Lock) go above.
        case .dictation: 57
        case .capsLock: 60
        case .level: 70
        }
    }

    /// Sticky activities that a glyph can sum up, so they can sit in a bubble.
    public var canBeBubble: Bool {
        switch self {
        case .media, .timer, .agent, .meeting, .external, .regionWatch: true
        default: false
        }
    }

    /// Short-lived cards and alerts the user can close early. Ongoing activities (music, a
    /// call, a timer, an agent at work), approvals and HUDs can't be.
    public var isDismissable: Bool {
        switch self {
        case .notification, .notice, .timerDone, .device, .battery, .focus, .meetingSoon, .tray, .downloadDone: true
        default: false
        }
    }
}
