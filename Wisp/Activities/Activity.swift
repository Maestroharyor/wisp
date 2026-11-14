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
    case agent(AgentStatus)
    /// A Claude Code permission prompt answered from the notch.
    case agentApproval(AgentApproval)
    /// The microphone is live: a call or a recording.
    case meeting(MeetingStatus)
    /// A call with a link starts in a couple of minutes.
    case meetingSoon(MeetingInvite)
    /// Headphones just connected, with their battery when they report it.
    case device(BluetoothDevice)
    /// A browser is downloading into a watched folder.
    case download(DownloadSummary)
    /// A download just finished, with Open and Show in Finder.
    case downloadDone(FinishedDownload)
    /// Posted by a script, Shortcut or link.
    case custom(ExternalActivity)
    /// Part of a window being watched for a change.
    case regionWatch(RegionWatchStatus)
    /// Wisp is listening for dictation while the key is held.
    case dictation(since: Date)
    /// What a quick add request will make, waiting for Add or Cancel.
    case quickIntent(QuickIntent)
    /// An AI action on selected or copied text: working, then the answer with Copy and Replace.
    case aiResult(AIResultCard)
    /// An agent session needs a decision: compact a full context, or carry on past the spend cap.
    case agentCallout(AgentCallout)

    /// Two-line card under the notch rather than a one-line pill.
    var isMedium: Bool {
        switch self {
        case .batteryFull, .timerDone: true
        default: false
        }
    }

    /// Level bars need room for the bar and the number, and a notice for a few words.
    var usesWideWings: Bool {
        switch self {
        case .level, .sent, .focus, .agent, .meeting, .device, .notice, .download, .custom, .regionWatch, .dictation:
            true
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
        case .agent: "agent"
        case .agentApproval(let approval): "agentApproval-\(approval.id)"
        case .meeting: "meeting"
        case .meetingSoon(let invite): "meetingSoon-\(invite.id)"
        case .device: "device"
        case .download: "download"
        case .downloadDone(let done): "downloadDone-\(done.path)"
        case .custom: "custom"
        case .regionWatch: "regionWatch"
        case .dictation: "dictation"
        case .quickIntent: "quickIntent"
        case .aiResult(let card): "aiResult-\(card.id)"
        case .agentCallout(let callout): "agentCallout-\(callout.id)"
        }
    }
}

/// A decision about an agent session that isn't one of its requests.
struct AgentCallout: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        /// The context passed Critical at; offers Compact now where the agent has `/compact`.
        case compact(percent: Int, canCompact: Bool)
        /// The session reached the spend cap: Keep going, Raise or Stop.
        case spendCap(SpendCap.Crossing, estimated: Bool)
    }

    let id = UUID()
    let sessionID: String
    let project: String
    let source: AgentSource
    let kind: Kind
}

/// The microphone in use: a call (named from the calendar, if anything) or a recording,
/// and when the mic came on.
struct MeetingStatus: Sendable, Equatable {
    let title: String
    let started: Date
    let kind: MicActivity
}

/// A call that's about to start, with its link.
struct MeetingInvite: Sendable, Equatable {
    let id: String
    let title: String
    let link: URL
    let start: Date
}

/// The running region watch: whose window, what it waits for, and whether low battery
/// has paused it.
struct RegionWatchStatus: Sendable, Equatable {
    let appName: String
    let rule: RegionWatchRule
    let paused: Bool
}

/// One AI action and, once the model has answered, its answer.
struct AIResultCard: Sendable, Equatable {
    let id: UUID
    let task: AITask
    let input: AITextInput
    /// Nil while the model works.
    var answer: AIAnswer?
}
