import AppKit
import SwiftUI
import WispCore

/// "Starts in 2 min" under the notch, with a Join button that opens the call link.
struct MeetingSoonCard: View {
    let invite: MeetingInvite
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.wispViolet)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.wispViolet.opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(invite.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(Self.startText(invite.start, now: context.date))
                            .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                // Already in this meeting's app (joined from the app): its mic and camera sit
                // beside Join, which stays for the next meeting. Never Leave here.
                if !controls.isEmpty {
                    MeetingControlsRow(states: controls, model: model)
                }
                joinButtons
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
    }

    /// The driven app's controls, only when this invite is for that app.
    private var controls: [MeetingControlState] {
        let driver = model.services.meetingControls
        guard let app = driver.app, MeetingControls.invite(invite.link, matches: app) else { return [] }
        return MeetingControls.joinCardStates(driver.states)
    }

    @ViewBuilder private var joinButtons: some View {
        CapsuleButton("Later") { model.services.activities.remove(.meetingSoon) }
        CapsuleButton("Join", prominent: true) {
            NSWorkspace.shared.open(invite.link)
            model.services.activities.remove(.meetingSoon)
        }
    }

    private static func startText(_ start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "Starting now" : "Starts in \(minutes) min"
    }
}

/// The meeting pill opened into the call app's own controls.
struct MeetingControlsCard: View {
    let status: MeetingStatus
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ValueText(
                            text: Countdown.format(max(0, context.date.timeIntervalSince(status.started))), tint: .red)
                    }
                    .font(.system(size: 12))
                }
                Spacer(minLength: 8)
                MeetingControlsRow(states: model.services.meetingControls.states, model: model)
                Button {
                    model.meetingControlsOpen = false
                } label: {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Color.secondaryText)
                .hoverHint("Hide call controls")
                .accessibilityLabel("Hide call controls")
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
    }
}

/// Round buttons for the call app's controls, in the order the app supports them. Each
/// shows its state when the app reports it (Zoom does; shortcut apps don't). Leave sits
/// apart and takes a second tap within a few seconds.
struct MeetingControlsRow: View {
    let states: [MeetingControlState]
    let model: NotchModel
    @State private var leave = LeaveConfirmation()

    var body: some View {
        HStack(spacing: 8) {
            ForEach(states) { state in
                if state.control == .leave {
                    leaveButton(state).padding(.leading, 10)
                } else {
                    Button {
                        model.services.meetingControls.perform(state.control)
                    } label: {
                        Image(systemName: state.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(state.engaged == true ? Color.wispViolet : .ink.opacity(0.14)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(state.engaged == true ? Color.white : Color.ink)
                    .hoverHint(state.help, help: state.help)
                    .accessibilityLabel(state.label)
                }
            }
        }
        .disabled(model.services.meetingControls.isPerforming)
        // Disarms Leave once its window passes, so the button goes back to the icon.
        .task(id: leave.armedAt) {
            guard leave.armedAt != nil else { return }
            try? await Task.sleep(for: .seconds(LeaveConfirmation.window))
            if !leave.isArmed(now: .now) { leave = LeaveConfirmation() }
        }
    }

    private func leaveButton(_ state: MeetingControlState) -> some View {
        let armed = leave.isArmed(now: .now)
        let tip = armed ? "Click again to leave the call" : state.help
        return Button {
            if leave.tap(now: .now) { model.services.meetingControls.perform(.leave) }
        } label: {
            Group {
                if armed {
                    Text(leave.label(now: .now)).font(.system(size: 12, weight: .bold)).padding(.horizontal, 10)
                } else {
                    Image(systemName: state.symbol).font(.system(size: 13, weight: .semibold)).frame(width: 30)
                }
            }
            .frame(height: 30)
            .background(Capsule().fill(.red))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .hoverHint(tip, help: tip)
        .accessibilityLabel(leave.label(now: .now))
    }
}
