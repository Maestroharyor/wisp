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

extension Color {
    /// The project's own colour, stable across launches.
    static func project(_ name: String) -> Color {
        Color(hue: ProjectColor.hue(for: name), saturation: 0.5, brightness: 1)
    }
}

extension AgentSource {
    var symbol: String { self == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right" }
}

/// The agent's mark in its project's colour, pulsing while it works.
struct AgentGlyph: View {
    let state: AgentSession.State
    let source: AgentSource
    let project: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A symbol effect follows `state` both ways. The earlier repeatForever animation started
    // only on appear, so it stuck dimmed after running → waiting → running.
    var body: some View {
        Image(systemName: state == .finished ? "checkmark.circle.fill" : source.symbol)
            .foregroundStyle(state == .finished ? state.tint : Color.project(project))
            .frame(width: 16)
            .symbolEffect(.pulse, options: .repeating, isActive: state == .running && !reduceMotion)
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
                Image(systemName: approval.source.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.project(approval.project))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.project(approval.project).opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(approval.tool).font(.system(size: 13, weight: .bold))
                        if let position = hub.queue.positionLabel {
                            Text(position)
                                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(.white.opacity(0.14)))
                        }
                        Button {
                            hub.focus(session: approval.sessionID)
                        } label: {
                            Label(approval.project, systemImage: "arrow.up.forward.app")
                                .font(.system(size: 11)).foregroundStyle(Color.project(approval.project))
                        }
                        .buttonStyle(.plain)
                        .help("Show the terminal")
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
/// They wake a moment after a request appears, so a click aimed at the previous card
/// can't answer the one that just replaced it.
struct ApprovalButtons: View {
    let approval: AgentApproval
    let hub: AgentHub

    @State private var ready = false

    var body: some View {
        HStack(spacing: 8) {
            Button("Deny") { hub.answer(approval.id, allow: false) }
                .buttonStyle(ApprovalButtonStyle(fill: .white.opacity(0.14), text: .white))
            Button("Allow All") { hub.allowAll(approval.id) }
                .buttonStyle(ApprovalButtonStyle(fill: .white.opacity(0.14), text: .white))
                .help("Allow this and every later request from \(approval.project) until the session ends")
            Button("Allow") { hub.answer(approval.id, allow: true) }
                .buttonStyle(ApprovalButtonStyle(fill: .wispGreen, text: .black))
        }
        .disabled(!ready)
        .opacity(ready ? 1 : 0.6)
        .task(id: approval.id) {
            ready = false
            try? await Task.sleep(for: .milliseconds(400))
            ready = true
        }
    }
}

/// A permission request while the shelf is open, where the card under the notch can't show.
struct ApprovalBar: View {
    let approval: AgentApproval
    let hub: AgentHub

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: approval.source.symbol).foregroundStyle(Color.project(approval.project))
            Text(approval.tool).font(.system(size: 12, weight: .bold))
            if let position = hub.queue.positionLabel {
                Text(position).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color.secondaryText)
            }
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
            if hub.connected.isEmpty {
                VStack(spacing: 6) {
                    Text("See Claude Code and Codex sessions here")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    Button("Connect Claude Code") { hub.installHooks(.claude) }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "sparkle").foregroundStyle(Color.wispViolet)
                    Text("No agent sessions").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(sessions) { session in
                            SessionRow(session: session) { hub.focus(session: session.id) }
                        }
                    }
                }
            }
        }
        .onAppear { hub.refreshInstalled() }
    }
}

/// One session: click to bring its terminal forward.
private struct SessionRow: View {
    let session: AgentSession
    let focus: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            AgentGlyph(state: session.state, source: session.source, project: session.project)
                .font(.system(size: 11))
            Text(session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if let usage = session.usage {
                Text(usage.summary(cost: session.cost))
                    .font(.system(size: 10)).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
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
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.project(session.project).opacity(hovering ? 0.22 : 0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: focus)
        .help("Show the terminal")
    }
}

/// The Agents widget opened on its own: sessions on the left; the selected one's history,
/// tokens and a prompt draft on the right.
struct AgentsDetail: View {
    let hub: AgentHub

    @State private var selection: String?
    @State private var draft = ""
    @State private var note: String?

    var body: some View {
        let sessions = hub.sessions.list
        let selected = sessions.first { $0.id == selection } ?? sessions.first
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Today ~$%.2f", hub.spend.total(on: .now)))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.secondaryText)
                if sessions.isEmpty {
                    Text("No agent sessions").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(sessions) { session in
                                DetailSessionRow(session: session, selected: session.id == selected?.id)
                                    .onTapGesture { selection = session.id }
                            }
                        }
                    }
                }
            }
            .frame(width: 190)

            if let selected {
                SessionDetail(session: selected, hub: hub, draft: $draft, note: $note)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { hub.refreshInstalled() }
    }
}

private struct DetailSessionRow: View {
    let session: AgentSession
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            AgentGlyph(state: session.state, source: session.source, project: session.project).font(.system(size: 11))
            Text(session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(session.state.label).font(.system(size: 10, weight: .medium)).foregroundStyle(session.state.tint)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.project(session.project).opacity(selected ? 0.28 : 0.1))
        )
        .contentShape(Rectangle())
    }
}

private struct SessionDetail: View {
    let session: AgentSession
    let hub: AgentHub
    @Binding var draft: String
    @Binding var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(session.usage.map { $0.summary(cost: session.cost) } ?? session.source.displayName)
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(1)
                Spacer()
                Button {
                    hub.focus(session: session.id)
                } label: {
                    Label("Terminal", systemImage: "arrow.up.forward.app").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.project(session.project))
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(session.timeline) { entry in
                            HStack(spacing: 6) {
                                Text(entry.date, format: .dateTime.hour().minute())
                                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(Color.secondaryText)
                                Image(systemName: entry.kind.symbol).font(.system(size: 9))
                                    .foregroundStyle(entry.kind.tint).frame(width: 12)
                                Text(entry.text).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            }
                            .id(entry.id)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(session.timeline.last?.id, anchor: .bottom) }
                // The timeline keeps the latest 40 entries, so its count stops changing; its last id doesn't.
                .onChange(of: session.timeline.last?.id) { proxy.scrollTo(session.timeline.last?.id, anchor: .bottom) }
            }
            HStack(spacing: 6) {
                TextField(note ?? "Draft a prompt…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))
                    .onSubmit(send)
                Button("Paste in Terminal", action: send)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.wispViolet.opacity(draft.isEmpty ? 0.3 : 0.9)))
                    .disabled(draft.isEmpty)
                    .help("Pastes into the session's terminal without sending; press Return there")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func send() {
        guard !draft.isEmpty else { return }
        if hub.sendDraft(draft, to: session.id) {
            draft = ""
            note = "Pasted. Press Return in the terminal to send."
        } else {
            note = "Allow Accessibility in Settings to paste"
        }
    }
}

extension AgentTimelineEntry.Kind {
    var symbol: String {
        switch self {
        case .started: "play.circle"
        case .prompt: "text.bubble"
        case .request: "hand.raised"
        case .allowed: "checkmark.circle"
        case .denied: "xmark.circle"
        case .waiting: "ellipsis.bubble"
        case .done: "flag.checkered"
        }
    }

    var tint: Color {
        switch self {
        case .started, .prompt: .white.opacity(0.7)
        case .request, .waiting: .wispAmber
        case .allowed, .done: .wispGreen
        case .denied: .red
        }
    }
}
