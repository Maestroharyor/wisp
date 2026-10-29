import SwiftUI
import WispCore

extension AgentSession.State {
    var tint: Color {
        switch self {
        case .idle: .secondaryText
        case .running: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .waiting, .needsApproval: .wispAmber
        case .finished: .wispGreen
        }
    }

    var label: String {
        switch self {
        case .idle: "Ready"
        case .running: "Working"
        case .waiting: "Needs you"
        case .needsApproval: "Approve?"
        case .finished: "Done"
        }
    }
}

/// Claude's spark, pulsing while it works.
struct AgentGlyph: View {
    let state: AgentSession.State
    @State private var pulse = false

    var body: some View {
        Image(systemName: state == .finished ? "checkmark.circle.fill" : "sparkle")
            .foregroundStyle(state.tint)
            .frame(width: 16)
            .scaleEffect(state == .running && pulse ? 0.8 : 1)
            .opacity(state == .running && pulse ? 0.6 : 1)
            .animation(
                state == .running ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: pulse
            )
            .onAppear { pulse = true }
    }
}

/// The pill's right side: elapsed time while working, otherwise the state.
struct AgentStateLabel: View {
    let status: AgentStatus

    var body: some View {
        if status.state == .running {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ValueText(
                    text: Countdown.format(max(0, context.date.timeIntervalSince(status.started))),
                    tint: status.state.tint)
            }
        } else {
            Text(status.state.label).lineLimit(1).foregroundStyle(status.state.tint)
        }
    }
}

/// The permission prompt under the notch: what Claude wants to run, and Allow or Deny.
struct AgentApprovalCard: View {
    let approval: AgentApproval
    let model: NotchModel

    var body: some View {
        let hub = model.services.agents
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AgentSession.State.running.tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AgentSession.State.running.tint.opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(approval.tool).font(.system(size: 13, weight: .bold))
                        Text(approval.project).font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    }
                    Text(approval.summary.isEmpty ? "Wants to use \(approval.tool)" : approval.summary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                ApprovalButtons(approval: approval, hub: hub)
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

/// Deny and Allow, shared by the card under the notch and the bar in an open shelf.
struct ApprovalButtons: View {
    let approval: AgentApproval
    let hub: AgentHub

    var body: some View {
        HStack(spacing: 8) {
            Button("Deny") { hub.answer(approval.id, allow: false) }
                .buttonStyle(ApprovalButtonStyle(fill: .white.opacity(0.14), text: .white))
            Button("Allow") { hub.answer(approval.id, allow: true) }
                .buttonStyle(ApprovalButtonStyle(fill: .wispGreen, text: .black))
        }
    }
}

/// A permission request while the shelf is open, where the card under the notch can't show.
struct ApprovalBar: View {
    let approval: AgentApproval
    let hub: AgentHub

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle").foregroundStyle(AgentSession.State.running.tint)
            Text(approval.tool).font(.system(size: 12, weight: .bold))
            Text(approval.summary.isEmpty ? approval.project : approval.summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            ApprovalButtons(approval: approval, hub: hub)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.5), radius: 10, y: -2)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ApprovalButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Every live Claude Code session, newest first.
struct AgentsWidget: View {
    let hub: AgentHub

    var body: some View {
        let sessions = hub.sessions.list
        Group {
            if !hub.hooksInstalled {
                VStack(spacing: 6) {
                    Text("See Claude Code sessions here").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    Button("Connect Claude Code") { hub.installHooks() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "sparkle").foregroundStyle(AgentSession.State.running.tint)
                    Text("No Claude Code sessions").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(sessions) { session in SessionRow(session: session) }
                    }
                }
            }
        }
        .onAppear { hub.refreshInstalled() }
    }
}

private struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            AgentGlyph(state: session.state).font(.system(size: 11))
            Text(session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if session.state == .running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Countdown.format(max(0, context.date.timeIntervalSince(session.turnStarted))))
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(session.state.tint)
                }
            } else {
                Text(session.state.label).font(.system(size: 11, weight: .medium)).foregroundStyle(session.state.tint)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(session.state.tint.opacity(0.12)))
    }
}
