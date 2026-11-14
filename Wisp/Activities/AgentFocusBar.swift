import SwiftUI
import WispCore

/// Under the Agents header: Keep awake (now, for an hour, or while agents work), Focus 25 and
/// 50 (the Pomodoro, with a fifth as much break), and Mute for an hour. Also opens the session
/// history when the "While you were away" card asks for it.
struct AgentFocusBar: View {
    let services: AppServices
    @Binding var showingHistory: Bool

    private var attention: AgentAttention { services.attention }

    var body: some View {
        HStack(spacing: 6) {
            KeepAwakeMenu(actions: services.quickActions, preferences: services.preferences)
            ForEach(Self.focusLengths, id: \.self) { length in
                FocusChip(minutes: length, timers: services.timers)
            }
            Spacer(minLength: 0)
            MuteButton(attention: attention)
        }
        .onAppear {
            if attention.takeHistoryRequest() { showingHistory = true }
        }
        .onChange(of: attention.historyRequests) {
            if attention.takeHistoryRequest() { showingHistory = true }
        }
    }

    private static let focusLengths = [25, 50]
}

private struct KeepAwakeMenu: View {
    let actions: QuickActions
    @Bindable var preferences: Preferences

    private var on: Bool { actions.keepAwake || preferences.agentKeepAwake }

    private var tip: String {
        if actions.keepAwake {
            guard let ends = actions.keepAwakeSession?.ends else { return "Keeping the Mac awake" }
            return "Keeping the Mac awake until \(ends.formatted(date: .omitted, time: .shortened))"
        }
        return preferences.agentKeepAwake ? "Keeping the Mac awake while agents work" : "Keep awake"
    }

    var body: some View {
        Menu {
            Button("Keep awake now") { actions.startKeepAwake(.lasting(nil, from: .now)) }
            Button("Keep awake for 1 hour") { actions.startKeepAwake(.lasting(3600, from: .now)) }
            Toggle("Keep awake while agents work", isOn: $preferences.agentKeepAwake)
            if actions.keepAwake {
                Divider()
                Button("Let the Mac sleep") { actions.endKeepAwake() }
            }
        } label: {
            Image(systemName: on ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.wispViolet : Color.secondaryText)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverHint(tip, edge: .bottom, help: tip)
        .accessibilityLabel(tip)
    }
}

/// Starts a focus session of `minutes`; while that length is running, stops it.
private struct FocusChip: View {
    let minutes: Int
    let timers: TimerStore

    private var running: Bool {
        timers.phase == .focus && timers.pomodoro.hasStarted && timers.focusMinutes == minutes
    }

    var body: some View {
        let tip = running ? "Stop the \(minutes) minute focus" : "Focus for \(minutes) minutes"
        Button {
            if running { timers.resetPomodoro() } else { timers.startFocus(minutes: minutes, rest: minutes / 5) }
        } label: {
            Text("\(minutes)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(
                    Capsule().fill(running ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.ink.opacity(0.1)))
                )
                .foregroundStyle(running ? Color.white : Color.secondaryText)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverHint(tip, edge: .bottom, help: tip)
        .accessibilityLabel(tip)
        .accessibilityAddTraits(running ? .isSelected : [])
    }
}

private struct MuteButton: View {
    let attention: AgentAttention

    var body: some View {
        let until = attention.mutedUntil
        let tip =
            until.map { "Agent alerts muted until \($0.formatted(date: .omitted, time: .shortened)); click to unmute" }
            ?? "Mute agent alerts for 1 hour"
        Button {
            if until == nil { attention.mute() } else { attention.unmute() }
        } label: {
            Image(systemName: until == nil ? "bell" : "bell.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(until == nil ? Color.secondaryText : Color.wispViolet)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHint(tip, edge: .bottom, help: tip)
        .accessibilityLabel(until == nil ? "Mute agent alerts for 1 hour" : "Unmute agent alerts")
    }
}
