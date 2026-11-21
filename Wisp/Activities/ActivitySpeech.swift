import Foundation
import SwiftUI
import WispCore

extension Activity {
    /// What VoiceOver says for the pill or card: one sentence for the whole thing.
    func spokenLabel(now: Date, thresholds: ContextUsage.Thresholds) -> String {
        switch self {
        case .level(let kind, let value, let muted):
            return AccessibilityText.level(
                name: kind == .volume ? "Volume" : "Display brightness", value: value, muted: muted)
        case .charging(let percent): return AccessibilityText.battery(percent: percent, charging: true, low: false)
        case .unplugged(let percent):
            return AccessibilityText.battery(percent: percent, charging: false, low: percent <= 20)
        case .lowBattery(let percent): return AccessibilityText.battery(percent: percent, charging: false, low: true)
        case .batteryFull: return "Battery full"
        case .capsLock(let on): return on ? "Caps Lock on" : "Caps Lock off"
        case .timer(let label, let countdown):
            return AccessibilityText.timer(label: label, remaining: countdown.remaining(now: now))
        case .timerDone(let label): return "\(label.isEmpty ? "Timer" : label) is done"
        case .media: return "Now playing"
        case .tray(let count): return "Tray, \(count) file\(count == 1 ? "" : "s")"
        case .notice(_, let text): return text
        case .notification(let item): return "Notification from \(item.appName): \(item.sender)"
        case .sent: return "Reply sent"
        case .focus(let state): return "\(state.name ?? "Focus") \(state.isOn ? "on" : "off")"
        case .agent(let status):
            let level = status.contextPercent.map { ContextUsage.level($0, thresholds: thresholds) } ?? .normal
            return AccessibilityText.agent(
                name: status.source.displayName, project: status.project, state: status.state.label,
                context: status.contextPercent.map { $0 / 100 }, warning: level != .normal)
        case .agentApproval(let approval): return "\(approval.source.displayName) in \(approval.project) needs approval"
        case .meeting: return "Microphone in use"
        case .meetingSoon: return "A call starts soon"
        case .device(let device): return "\(device.name) connected"
        case .download(let summary):
            return summary.count == 1 ? "Downloading" : "Downloading \(summary.count) files"
        case .downloadDone: return "Download finished"
        case .custom(let activity): return activity.title
        case .regionWatch(let status): return "Watching \(status.appName)\(status.paused ? ", paused" : "")"
        case .dictation: return "Listening"
        case .quickIntent: return "Quick add, waiting for Add or Cancel"
        case .aiResult: return "AI result"
        case .agentCallout: return "An agent session needs a decision"
        case .agentAway: return "What agents did while you were away"
        }
    }
}

/// A pill or card read as one element: its sentence, a button that does what a click does, and
/// on the orb a way to the ring.
struct PillAccessibility: ViewModifier {
    let activity: Activity
    let model: NotchModel

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.spokenLabel(now: .now, thresholds: model.preferences.contextThresholds))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows its details")
            .accessibilityAction { model.onAccessibilityOpen() }
            .accessibilityAction(named: "Open ring") { model.onAccessibilityRing() }
    }
}
