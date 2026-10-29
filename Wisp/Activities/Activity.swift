import SwiftUI
import WispCore

enum LevelKind: Sendable, Equatable {
    case volume
    case brightness

    func symbol(value: Double, muted: Bool) -> String {
        switch self {
        case .volume:
            if muted || value <= 0 { return "speaker.slash.fill" }
            return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness:
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }

    func tint(muted: Bool) -> Color {
        switch self {
        case .volume: muted ? .red : .green
        case .brightness: .yellow
        }
    }
}

/// A notification ready to show, with its reply channel when Wisp can answer it.
struct NotificationItem: Sendable, Equatable, Identifiable {
    let id: Int64
    let appID: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    let channel: ReplyChannel?

    /// Who it is from: the title, or the app when there is none.
    var sender: String { title.isEmpty ? appName : title }
}

/// Everything that can appear beside the notch while it is closed.
enum Activity: Sendable, Equatable {
    case level(LevelKind, value: Double, muted: Bool)
    case charging(percent: Int)
    case unplugged(percent: Int)
    case lowBattery(percent: Int)
    case batteryFull
    case capsLock(on: Bool)
    case timer(label: String, countdown: Countdown)
    case timerDone(label: String)
    case media
    case tray(count: Int)
    case notice(symbol: String, text: String)
    case notification(NotificationItem)
    /// Confirmation after a reply was sent.
    case sent(text: String)
    case focus(FocusModeState)

    /// Two-line card under the notch rather than a one-line pill.
    var isMedium: Bool {
        switch self {
        case .batteryFull, .timerDone: true
        default: false
        }
    }

    /// Level bars need room for the bar and the number.
    var usesWideWings: Bool {
        switch self {
        case .level, .sent, .focus: true
        default: false
        }
    }

    /// Stable identity for animation: changes only when the kind of activity changes,
    /// so a volume step updates in place instead of re-running the morph.
    var kindKey: String {
        switch self {
        case .level(let kind, _, _): "level-\(kind)"
        case .charging: "charging"
        case .unplugged: "unplugged"
        case .lowBattery: "lowBattery"
        case .batteryFull: "batteryFull"
        case .capsLock: "capsLock"
        case .timer: "timer"
        case .timerDone: "timerDone"
        case .media: "media"
        case .tray: "tray"
        case .notice(let symbol, _): "notice-\(symbol)"
        case .notification(let item): "notification-\(item.id)"
        case .sent: "sent"
        case .focus: "focus"
        }
    }
}

/// Priorities and lifetimes for each activity source. Higher wins.
enum ActivitySlot: String {
    case media
    case timer
    case tray
    case battery
    case notice
    case notification
    case focus
    case capsLock
    case level

    var priority: Int {
        switch self {
        case .media: 10
        case .timer: 20
        case .tray: 30
        case .battery: 40
        case .notice: 45
        case .focus: 42
        case .notification: 50
        case .capsLock: 60
        case .level: 70
        }
    }
}
