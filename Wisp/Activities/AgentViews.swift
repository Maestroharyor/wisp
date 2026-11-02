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

extension ContextUsage.Level {
    var tint: Color {
        switch self {
        case .normal: .wispViolet
        case .warning: .wispAmber
        case .critical: .red
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

/// The agent's mark in its project's colour, pulsing while it works, ringed by how full
/// its context window is when the agent reports it.
struct AgentGlyph: View {
    let state: AgentSession.State
    let source: AgentSource
    let project: String
    var context: Double? = nil
    /// Other live sessions, shown as a "+N" badge.
    var others = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A symbol effect follows `state` both ways. The earlier repeatForever animation started
    // only on appear, so it stuck dimmed after running → waiting → running.
    var body: some View {
        Image(systemName: state == .finished ? "checkmark.circle.fill" : source.symbol)
            .foregroundStyle(state == .finished ? state.tint : Color.project(project))
            .frame(width: 16)
            .symbolEffect(.pulse, options: .repeating, isActive: state == .running && !reduceMotion)
            .overlay {
                if let context, state != .finished { ContextRing(percent: context).frame(width: 19, height: 19) }
            }
            .overlay(alignment: .topTrailing) {
                if others > 0 {
                    Text("+\(others)")
                        .font(.system(size: 8, weight: .bold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 2.5)
                        .frame(minHeight: 10)
                        .background(Capsule().fill(Color.wispViolet))
                        .fixedSize()
                        .offset(x: 10, y: -7)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        [
            context.map { "\(Int($0.rounded()))% context used" },
            others > 0 ? "\(others) more \(others == 1 ? "session" : "sessions")" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A thin ring filled to the share of the context window in use.
struct ContextRing: View {
    let percent: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: min(max(percent, 0), 100) / 100)
                .stroke(ContextUsage.level(percent).tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: percent)
    }
}

/// A short bar for the context window, with its percentage.
struct ContextBar: View {
    let percent: Double

    var body: some View {
        HStack(spacing: 4) {
            Capsule().fill(.white.opacity(0.14)).frame(width: 36, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(ContextUsage.level(percent).tint)
                        .frame(width: 36 * min(max(percent, 0), 100) / 100, height: 4)
                }
            Text("\(Int(percent.rounded()))%").font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(ContextUsage.level(percent).tint)
        }
        .help("Context window used")
    }
}

/// The pill's right side: the running tool (with tool activity on) or the elapsed time
/// while working, otherwise the state. The upright pill on a side edge is too narrow for
/// a tool, so it passes `showsTool: false`.
struct AgentStateLabel: View {
    let status: AgentStatus
    var showsTool = true

    var body: some View {
        if status.compacting {
            Text("Compacting…").lineLimit(1).foregroundStyle(Color.wispViolet)
        } else if showsTool, let tool = status.tool {
            HStack(spacing: 4) {
                Image(systemName: tool.symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(status.state.tint)
                Text(tool.short).lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tool.label)
        } else if status.state == .running {
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
                        Text(approval.title).font(.system(size: 13, weight: .bold))
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
                    ApprovalSummary(
                        approval: approval, hidden: hub.detailsHidden,
                        fallback: approval.prompt == .plan ? "Plan ready for review" : "Wants to use \(approval.tool)",
                        size: 12, lines: 2
                    )
                    .id(approval.id)
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

/// The command or path a request wants to use. In private mode it's hidden until "Show" is
/// pressed for this request, so nothing is approved unseen.
private struct ApprovalSummary: View {
    let approval: AgentApproval
    let hidden: Bool
    let fallback: String
    let size: CGFloat
    let lines: Int

    @State private var revealed = false

    var body: some View {
        if hidden && !revealed && !approval.summary.isEmpty {
            HStack(spacing: 6) {
                Label("Details hidden", systemImage: "eye.slash")
                    .font(.system(size: size)).foregroundStyle(.white.opacity(0.7))
                Button("Show") { revealed = true }
                    .font(.system(size: size - 1, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.wispViolet)
                    .help("Show this request's command or file")
            }
        } else {
            Text(AgentPrivacy.summary(approval.summary, hidden: false) ?? fallback)
                .font(.system(size: size, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(lines)
                .truncationMode(.middle)
        }
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
            // Allow All covers tool calls only; each plan is approved on its own.
            if approval.prompt == .tool {
                Button("Allow All") { hub.allowAll(approval.id) }
                    .buttonStyle(ApprovalButtonStyle(fill: .white.opacity(0.14), text: .white))
                    .help("Allow this and every later request from \(approval.project) until the session ends")
            }
            Button(approval.prompt == .plan ? "Approve" : "Allow") { hub.answer(approval.id, allow: true) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let approval: AgentApproval
    let hub: AgentHub

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: approval.source.symbol).foregroundStyle(Color.project(approval.project))
            Text(approval.title).font(.system(size: 12, weight: .bold))
            if let position = hub.queue.positionLabel {
                Text(position).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color.secondaryText)
            }
            ApprovalSummary(
                approval: approval, hidden: hub.detailsHidden, fallback: approval.project, size: 11, lines: 1
            )
            .id(approval.id)
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
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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
/// Each agent session as a status bar, like the one in the terminal. At the Wide size the
/// widget shows `AgentsDetail` instead, with the selected session's details on the right.
struct AgentsWidget: View {
    let hub: AgentHub

    var body: some View {
        let sessions = hub.sessions.list
        Group {
            if hub.connected.isEmpty {
                ConnectAgentsHint(hub: hub)
            } else if sessions.isEmpty {
                NoSessionsHint()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(sessions) { session in
                            SessionBar(session: session) { hub.focus(session: session.id) }
                                .help("Show the terminal")
                        }
                    }
                }
            }
        }
        .onAppear { hub.refreshInstalled() }
    }
}

private struct ConnectAgentsHint: View {
    let hub: AgentHub

    var body: some View {
        VStack(spacing: 6) {
            Text("See Claude Code and Codex sessions here")
                .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            Button("Connect Claude Code") { hub.installHooks(.claude) }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoSessionsHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "sparkle").foregroundStyle(Color.wispViolet)
            Text("No agent sessions").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Elapsed time while working, "Compacting…", or the state with how long the last turn took.
private struct SessionStateText: View {
    let session: AgentSession

    var body: some View {
        Group {
            if session.compacting {
                Text("Compacting…").foregroundStyle(Color.wispViolet)
            } else if session.state == .running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Countdown.format(max(0, context.date.timeIntervalSince(session.turnStarted))))
                        .monospacedDigit()
                        .foregroundStyle(session.state.tint)
                }
            } else if session.state == .finished, let took = session.lastTurnDuration {
                Text("Done in \(Countdown.format(took))").monospacedDigit().foregroundStyle(session.state.tint)
            } else {
                Text(session.state.label).foregroundStyle(session.state.tint)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }
}

/// One session in the terminal bar's order: project, branch and model with its state, then
/// context, cost, tokens and lines changed. Figures nobody reported are left out; when the
/// widget is narrow the last ones go first, as in the terminal.
private struct SessionBar: View {
    let session: AgentSession
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                AgentGlyph(
                    state: session.state, source: session.source, project: session.project,
                    context: session.contextPercent
                )
                .font(.system(size: 12))
                TerminalIcon(bundleID: session.terminal, size: 14)
                Text(session.project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let branch = session.branch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let model = session.displayModel {
                    Text(model).font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 4)
                SessionStateText(session: session)
            }
            if partCount > 0 {
                ViewThatFits(in: .horizontal) {
                    ForEach((0..<partCount).reversed(), id: \.self) { dropped in
                        figures(keeping: partCount - dropped)
                    }
                }
                .padding(.leading, 25)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.project(session.project).opacity(hovering ? 0.22 : 0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityAddTraits(.isButton)
    }

    private enum Part: Hashable {
        case context(Double)
        case cost(String)
        case tokens(String)
        case lines(added: Int, removed: Int)
    }

    /// In the order they're kept.
    private var parts: [Part] {
        var result: [Part] = []
        if let percent = session.contextPercent { result.append(.context(percent)) }
        if let cost = session.cost {
            result.append(.cost((session.costIsReal ? "" : "~") + String(format: "$%.2f", cost)))
        }
        if let usage = session.usage { result.append(.tokens(usage.summary(cost: nil))) }
        if session.linesAdded > 0 || session.linesRemoved > 0 {
            result.append(.lines(added: session.linesAdded, removed: session.linesRemoved))
        }
        return result
    }

    private var partCount: Int { parts.count }

    private func figures(keeping count: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(parts.prefix(count)), id: \.self) { part in
                switch part {
                case .context(let percent): ContextBar(percent: percent)
                case .cost(let text): Text(text)
                case .tokens(let text): Text(text).foregroundStyle(Color.secondaryText)
                case .lines(let added, let removed):
                    HStack(spacing: 4) {
                        Text("+\(added)").foregroundStyle(Color.wispGreen)
                        Text("−\(removed)").foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

/// The Agents widget opened on its own: sessions on the left; the selected one's history,
/// tokens and a prompt draft on the right.
struct AgentsDetail: View {
    let hub: AgentHub
    let model: NotchModel

    @State private var selection: String?
    @State private var note: String?

    var body: some View {
        let sessions = hub.sessions.list
        let selected = sessions.first { $0.id == selection } ?? sessions.first
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SpendTrend(spend: hub.spend)
                    Spacer(minLength: 0)
                    PrivacyButton(hub: hub)
                }
                if hub.connected.isEmpty {
                    ConnectAgentsHint(hub: hub)
                } else if sessions.isEmpty {
                    NoSessionsHint()
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
                SessionDetail(
                    session: selected, hub: hub, hidden: hub.detailsHidden, draft: draft(for: selected.id),
                    note: $note)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { hub.refreshInstalled() }
        .onChange(of: selected?.id) { note = nil }
    }

    private func draft(for session: String) -> Binding<String> {
        Binding(
            get: { model.agentDrafts[session] ?? "" },
            set: { model.agentDrafts[session] = $0.isEmpty ? nil : $0 })
    }
}

/// Today's spend with a week of days behind it.
private struct SpendTrend: View {
    let spend: DailySpend

    var body: some View {
        // Redrawn each minute so "today" moves over at midnight without waiting for an event.
        TimelineView(.everyMinute) { context in trend(at: context.date) }
    }

    private func trend(at now: Date) -> some View {
        let week = spend.recent(days: 7, ending: now)
        let peak = week.max() ?? 0
        let weekTotal = week.reduce(0, +)
        return HStack(spacing: 6) {
            Text(String(format: "Today ~$%.2f", week.last ?? 0))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.secondaryText)
                .lineLimit(1).fixedSize()
            if weekTotal > 0 {
                Sparkline(values: week.map { peak > 0 ? $0 / peak : 0 }, tint: .wispViolet, filled: true)
                    .frame(width: 40, height: 14)
            }
        }
        .help(String(format: "Last 7 days ~$%.2f", weekTotal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: "Spend today about %.2f dollars, last 7 days about %.2f dollars", week.last ?? 0, weekTotal))
    }
}

/// The manual switch. While a call or Settings hide details it can't show them, so it says
/// why instead of offering to hide what's already hidden.
private struct PrivacyButton: View {
    let hub: AgentHub

    var body: some View {
        let locked = hub.hiddenByRule
        Button {
            hub.hideNow.toggle()
        } label: {
            Image(systemName: hub.detailsHidden ? "eye.slash" : "eye")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hub.detailsHidden ? Color.wispViolet : Color.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .help(
            hub.hiddenReason.map { "Commands and file names are hidden \($0)" + (locked ? "" : "; click to show") }
                ?? "Hide commands and file names"
        )
        .accessibilityLabel(
            locked
                ? "Agent details hidden \(hub.hiddenReason ?? "")"
                : hub.hideNow ? "Show agent details" : "Hide agent details")
    }
}

private struct DetailSessionRow: View {
    let session: AgentSession
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                AgentGlyph(
                    state: session.state, source: session.source, project: session.project,
                    context: session.contextPercent
                )
                .font(.system(size: 11))
                TerminalIcon(bundleID: session.terminal, size: 13)
                Text(session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                SessionStateText(session: session)
            }
            if let branch = session.branch {
                Text(branch).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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
    let hidden: Bool
    @Binding var draft: String
    @Binding var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                if let percent = session.contextPercent { ContextBar(percent: percent) }
                Spacer()
                action(TerminalApps.name(for: session.terminal) ?? "Terminal", symbol: "arrow.up.forward.app") {
                    hub.focus(session: session.id)
                }
                if !session.cwd.isEmpty {
                    action("Folder", symbol: "folder") { hub.openFolder(session: session.id) }
                }
                if session.transcriptPath != nil {
                    action("Transcript", symbol: "doc.text") {
                        if !hub.revealTranscript(session: session.id) { note = "Transcript not found" }
                    }
                    .help("Show the transcript in Finder")
                }
                // Wisp's clipboard history would show the ID, so it isn't offered while private.
                if !hidden {
                    action("Copy ID", symbol: "doc.on.doc") {
                        hub.copyID(session: session.id)
                        note = "Session ID copied"
                    }
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
                            ForEach(session.facts(now: context.date, hidden: hidden)) { fact in
                                GridRow {
                                    Text(fact.label).foregroundStyle(Color.secondaryText)
                                    Text(fact.value).textSelection(.enabled).lineLimit(2)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .font(.system(size: 11))
                    }
                    Divider().opacity(0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(session.timeline) { entry in
                            HStack(spacing: 6) {
                                Text(entry.date, format: .dateTime.hour().minute())
                                    .font(.system(size: 10)).monospacedDigit()
                                    .foregroundStyle(Color.secondaryText)
                                Image(systemName: entry.kind.symbol).font(.system(size: 9))
                                    .foregroundStyle(entry.kind.tint).frame(width: 12)
                                Text(entry.display(hidden: hidden)).font(.system(size: 11)).lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .id(entry.id)
                        }
                    }
                }
            }
            if hidden {
                Label(note ?? "Prompt drafts are hidden while details are private", systemImage: "eye.slash")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    .frame(height: 24)
            } else {
                draftBox
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var draftBox: some View {
        HStack(spacing: 6) {
            TextField(note ?? "Draft a prompt…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))
                .onSubmit(send)
            Button("Paste in \(TerminalApps.name(for: session.terminal) ?? "Terminal")", action: send)
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Color.wispViolet.opacity(draft.isEmpty ? 0.3 : 0.9)))
                .disabled(draft.isEmpty)
                .help("Pastes into the session's terminal without sending; press Return there")
        }
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.project(session.project))
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
        case .answered: "arrowshape.turn.up.left"
        case .done: "flag.checkered"
        case .compacted: "arrow.down.right.and.arrow.up.left"
        }
    }

    var tint: Color {
        switch self {
        case .started, .prompt, .answered: .white.opacity(0.7)
        case .request, .waiting: .wispAmber
        case .allowed, .done: .wispGreen
        case .denied: .red
        case .compacted: .wispViolet
        }
    }
}
