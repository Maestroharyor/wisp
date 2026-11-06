import Foundation

/// Where each live activity source posts, and the rules that decide how it competes for
/// the notch. Higher priority wins the main pill.
public enum ActivitySlot: String, CaseIterable, Sendable {
    case media
    case timer
    case tray
    case battery
    case notice
    case notification
    case focus
    case capsLock
    case level
    case agent
    case agentApproval
    case meeting
    case meetingSoon
    case device

    public var priority: Int {
        switch self {
        case .media: 10
        case .agent: 15
        case .agentApproval: 55
        case .meeting: 44
        case .meetingSoon: 48
        case .timer: 20
        case .tray: 30
        case .battery: 40
        case .device: 41
        case .notice: 45
        case .focus: 42
        case .notification: 50
        case .capsLock: 60
        case .level: 70
        }
    }

    /// Sticky activities that a glyph can sum up, so they can sit in a bubble.
    public var canBeBubble: Bool {
        switch self {
        case .media, .timer, .agent, .meeting: true
        default: false
        }
    }
}
