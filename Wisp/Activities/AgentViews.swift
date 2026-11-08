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
    var symbol: String { adapter.symbol }
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
            Circle().stroke(.ink.opacity(0.14), lineWidth: 1.5)
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
            Capsule().fill(.ink.opacity(0.14)).frame(width: 36, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(ContextUsage.level(percent).tint)
                        .frame(width: 36 * min(max(percent, 0), 100) / 100, height: 4)
                }
            Text("\(Int(percent.rounded()))%").font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(ContextUsage.level(percent).tint)
                .lineLimit(1).fixedSize()
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
        if approval.prompt == .question {
            AgentQuestionCard(approval: approval, model: model)
        } else {
            requestCard
        }
    }

    private var requestCard: some View {
        let hub = model.services.agents
        return VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: approval.source.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.project(approval.project))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.project(approval.project).opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        // One line each; the project name gives way first when the card is narrow.
                        Text(approval.title).font(.system(size: 13, weight: .bold))
                            .lineLimit(1).fixedSize()
                        if let position = hub.queue.positionLabel {
                            Text(position)
                                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(.ink.opacity(0.14)))
                        }
                        Button {
                            hub.focus(session: approval.sessionID)
                        } label: {
                            Label(approval.project, systemImage: "arrow.up.forward.app")
                                .font(.system(size: 11)).foregroundStyle(Color.project(approval.project))
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        .help("Show the terminal")
                        // Private mode keeps the diff, command and plan out of sight too.
                        if approval.preview != nil, !hub.detailsHidden {
                            Button {
                                model.expandedApproval = expanded ? nil : approval.id
                            } label: {
                                Label(
                                    expanded ? "Less" : "Preview", systemImage: expanded ? "chevron.up" : "chevron.down"
                                )
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.wispViolet)
                                .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .help(approval.prompt == .plan ? "Read the plan" : "See what it will change")
                        }
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
            // The full preview replaces it when open; private mode shows neither.
            if !expanded, let diff = approval.inlineDiff, !hub.detailsHidden {
                InlineDiffView(diff: diff)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .frame(height: SurfaceSizing.inlineDiffHeight, alignment: .top)
                    .transition(.opacity)
            }
            if expanded, let preview = approval.preview, !hub.detailsHidden {
                VStack(spacing: 8) {
                    ApprovalPreviewPane(preview: preview)
                    DenyReasonRow(approval: approval, model: model)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
                .frame(height: SurfaceSizing.approvalPreviewHeight)
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
    }

    private var expanded: Bool { model.expandedApproval == approval.id }
}

/// The diff, command, new file or plan behind a request, scrolled inside the card.
private struct ApprovalPreviewPane: View {
    let preview: ApprovalPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                switch preview {
                case .diff(let lines, let more):
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.kind.marker + line.text)
                            .foregroundStyle(line.kind.tint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(line.kind.tint.opacity(line.kind == .context ? 0 : 0.12))
                    }
                    moreLines(more)
                case .text(let text, let more):
                    Text(text).foregroundStyle(.ink.opacity(0.85))
                    moreLines(more)
                case .markdown(let plan):
                    Text(Self.markdown(plan)).font(.system(size: 12)).foregroundStyle(.ink.opacity(0.9))
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ink.opacity(0.06)))
    }

    @ViewBuilder private func moreLines(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count) more lines").foregroundStyle(Color.secondaryText).padding(.top, 4)
        }
    }

    /// Bold, code and links render; headings and lists stay as written, line breaks and all.
    private static func markdown(_ plan: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: plan, options: options)) ?? AttributedString(plan)
    }
}

extension DiffLine.Kind {
    fileprivate var marker: String {
        switch self {
        case .context: "  "
        case .removed: "- "
        case .added: "+ "
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .context: .ink.opacity(0.6)
        case .removed: .red
        case .added: .wispGreen
        }
    }
}

/// The first changed lines of an edit, in the card itself, with the whole change's counts.
private struct InlineDiffView: View {
    let diff: InlineDiff

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        if let number = line.number {
                            Text("\(number)").foregroundStyle(Color.secondaryText)
                                .frame(minWidth: 18, alignment: .trailing)
                        }
                        Text(line.kind.marker + line.text).foregroundStyle(line.kind.tint)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.kind.tint.opacity(0.12))
                }
            }
            Group {
                if diff.wholeFile {
                    Text(diff.counts).foregroundStyle(Color.secondaryText)
                        .help("The file's whole new content")
                        .accessibilityLabel("New content, \(diff.counts)")
                } else {
                    HStack(spacing: 4) {
                        Text("+\(diff.added)").foregroundStyle(Color.wispGreen)
                        Text("−\(diff.removed)").foregroundStyle(.red.opacity(0.85))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(diff.added) lines added, \(diff.removed) removed")
                }
            }
            .fixedSize()
        }
        .font(.system(size: 11, design: .monospaced))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ink.opacity(0.06)))
    }
}

/// "Reason…" opens a field; Deny then tells Claude what to do instead.
private struct DenyReasonRow: View {
    let approval: AgentApproval
    let model: NotchModel

    @State private var typing = false
    @State private var reason = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if typing {
                TextField(
                    approval.prompt == .plan ? "What should change?" : "Why not, or what to do instead", text: $reason
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(deny)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(.ink.opacity(0.1)))
                Button("Cancel", action: stopTyping)
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.ink.opacity(0.7))
                Button("Deny", action: deny)
                    .buttonStyle(.plain).font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Capsule().fill(.ink.opacity(0.14)))
            } else {
                Button("Deny with a reason…") {
                    typing = true
                    model.onWantsKey()
                    focused = true
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.wispViolet)
                Spacer()
            }
        }
        .frame(height: 28)
        // Collapsing the preview mid-reason mustn't leave the notch holding the keyboard.
        .onDisappear { if typing { model.onKeyDone() } }
    }

    private func stopTyping() {
        typing = false
        reason = ""
        model.onKeyDone()
    }

    private func deny() {
        model.services.agents.deny(approval.id, reason: reason)
        stopTyping()
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
                    .font(.system(size: size)).foregroundStyle(.ink.opacity(0.7))
                Button("Show") { revealed = true }
                    .font(.system(size: size - 1, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.wispViolet)
                    .help("Show this request's command or file")
            }
        } else {
            Text(AgentPrivacy.summary(approval.summary, hidden: false) ?? fallback)
                .font(.system(size: size, design: .monospaced))
                .foregroundStyle(.ink.opacity(0.85))
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
        let hyper = hub.keysUseHyper()
        HStack(spacing: 8) {
            Button {
                hub.answer(approval.id, allow: false)
            } label: {
                KeyHintLabel(title: "Deny", hint: ApprovalKeys.hint(.deny, hyper: hyper))
            }
            .buttonStyle(ApprovalButtonStyle(fill: .ink.opacity(0.14), text: .ink))
            // Allow All covers tool calls only; each plan is approved on its own.
            if approval.prompt == .tool {
                Button("Allow All") { hub.allowAll(approval.id) }
                    .buttonStyle(ApprovalButtonStyle(fill: .ink.opacity(0.14), text: .ink))
                    .help("Allow this and every later request from \(approval.project) until the session ends")
            }
            if approval.prompt == .tool, !approval.rules.isEmpty { AlwaysAllowMenu(approval: approval, hub: hub) }
            Button {
                hub.answer(approval.id, allow: true)
            } label: {
                KeyHintLabel(
                    title: approval.prompt == .plan ? "Approve" : "Allow", hint: ApprovalKeys.hint(.allow, hyper: hyper)
                )
            }
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
    let model: NotchModel

    var body: some View {
        Group {
            if approval.prompt == .question {
                questionBar
            } else {
                requestBar
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.5), radius: 10, y: -2)
        )
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    private var questionBar: some View {
        QuestionAnswers(approval: approval, hub: hub, model: model) { step in
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(Color.project(approval.project))
                Text(step.header).font(.system(size: 12, weight: .bold))
                if let position = step.position {
                    Text(position).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Color.secondaryText)
                }
                Text(step.text).font(.system(size: 11)).foregroundStyle(.ink.opacity(0.85)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
    }

    private var requestBar: some View {
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
    }
}

/// A button's title with its shortcut beside it, dimmed ("Allow ⇪ Y").
struct KeyHintLabel: View {
    let title: String
    let hint: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            if let hint {
                Text(hint).font(.system(size: 10, weight: .semibold)).opacity(0.6).accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .help(hint.map { "\(title) (\($0))" } ?? title)
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
    let cloud: CloudAgentStore

    var body: some View {
        let sessions = hub.sessions.list
        let hasCloud = !CloudLane.visible(cloud.tasks, now: .now).isEmpty
        Group {
            if sessions.isEmpty && !hasCloud {
                if hub.connected.isEmpty { ConnectAgentsHint(hub: hub) } else { NoSessionsHint() }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        LimitsHeader(readings: hub.limitReadings)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(sessions) { session in
                            SessionBar(session: session, hidden: hub.detailsHidden) { hub.focus(session: session.id) }
                                .help("Show the terminal")
                        }
                        CloudTasksLane(store: cloud, hidden: hub.detailsHidden)
                    }
                }
            }
        }
        .onAppear {
            hub.refreshInstalledIfStale()
            cloud.refreshNow()
        }
    }
}

private struct ConnectAgentsHint: View {
    let hub: AgentHub

    var body: some View {
        VStack(spacing: 6) {
            Text("See \(ListFormatter.localizedString(byJoining: AgentAdapters.all.map(\.displayName))) sessions here")
                .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            // The first adapter is the main one; Settings connects the rest.
            if let main = AgentAdapters.all.first {
                Button("Connect \(main.displayName)") { hub.installHooks(main.source) }.controlSize(.small)
            }
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

extension SessionGlance.Activity {
    var symbol: String {
        switch self {
        case .tool(let tool): tool.symbol
        case .compacting: "arrow.down.right.and.arrow.up.left"
        case .working: "ellipsis"
        case .approval: "hand.raised"
        case .waiting: "ellipsis.bubble"
        case .done: "arrow.up.forward.app"
        case .ready: "circle"
        }
    }

    var tint: Color {
        switch self {
        case .tool, .compacting, .working: .wispViolet
        case .approval, .waiting: .wispAmber
        case .done: .wispGreen
        case .ready: .secondaryText
        }
    }
}

/// Under a session's title: "You: <last prompt>" (left out while details are private), what
/// it's doing now, then its agent and terminal tags with how long it's been in this state.
/// With `jump`, a finished session's line brings its terminal forward; without it the row's
/// own tap decides (the detail list selects).
private struct SessionGlanceLines: View {
    let glance: SessionGlance
    let terminal: String?
    var jump: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let prompt = glance.prompt {
                Text(prompt).font(.system(size: 11)).foregroundStyle(.ink.opacity(0.75))
                    .lineLimit(1).truncationMode(.tail)
            }
            if glance.activity == .done, let jump {
                Button(action: jump) { activity }
                    .buttonStyle(.plain)
                    .help("Show the terminal")
            } else {
                activity
            }
            HStack(spacing: 4) {
                SessionTag(text: glance.agent)
                if let name = TerminalApps.name(for: terminal) { SessionTag(text: name) }
                Spacer(minLength: 4)
                Text(glance.age).font(.system(size: 10)).monospacedDigit().foregroundStyle(Color.secondaryText)
                    .lineLimit(1).fixedSize()
            }
        }
    }

    private var activity: some View {
        Label(glance.activity.text, systemImage: glance.activity.symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(glance.activity.tint)
            .lineLimit(1).truncationMode(.middle)
    }
}

private struct SessionTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(.ink.opacity(0.1)))
    }
}

/// The account's usage windows over the sessions list: percent used and time to reset.
/// Windows nobody reported are left out, and the header with them.
private struct LimitsHeader: View {
    let readings: [UsageReading]

    var body: some View {
        if !readings.isEmpty {
            TimelineView(.everyMinute) { context in
                let items = LimitSummary.make(readings, now: context.date)
                if !items.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { ForEach(items, id: \.label, content: LimitItem.init) }
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(items, id: \.label, content: LimitItem.init)
                        }
                    }
                }
            }
        }
    }
}

private struct LimitItem: View {
    let item: LimitSummary

    var body: some View {
        HStack(spacing: 4) {
            Text(item.label).foregroundStyle(Color.secondaryText)
            Capsule().fill(.ink.opacity(0.14)).frame(width: 28, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: 28 * CGFloat(item.percent) / 100, height: 4)
                }
            Text("\(item.percent)%").foregroundStyle(tint)
            if let resets = item.resetsIn { Text(resets).foregroundStyle(Color.secondaryText) }
        }
        .font(.system(size: 10, weight: .medium)).monospacedDigit()
        .lineLimit(1).fixedSize()
        .help(
            item.resetsIn.map { "\(item.label) limit \(item.percent)% used, resets in \($0)" } ?? "\(item.label) limit"
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.label) limit \(item.percent) percent used" + (item.resetsIn.map { ", resets in \($0)" } ?? ""))
    }

    /// The same levels the limit alerts use.
    private var tint: Color {
        let percent = Double(item.percent)
        if percent >= (LimitWatch.levels.last ?? 95) { return .red }
        if percent >= (LimitWatch.levels.first ?? 80) { return .wispAmber }
        return .wispViolet
    }
}

/// One session in the terminal bar's order: project, branch and model with its state, then
/// context, cost, tokens and lines changed. Figures nobody reported are left out; when the
/// widget is narrow the last ones go first, as in the terminal.
private struct SessionBar: View {
    let session: AgentSession
    let hidden: Bool
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
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                SessionGlanceLines(
                    glance: SessionGlance.make(session, now: context.date, hidden: hidden), terminal: session.terminal,
                    jump: open)
            }
            .padding(.leading, 25)
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
    let cloud: CloudAgentStore
    let model: NotchModel

    @State private var selection: String?
    @State private var showingHistory = false
    @State private var note: String?
    /// This view's claim on dictation's draft box target; see `DraftBoxClaim`.
    @State private var owner = UUID()

    var body: some View {
        let sessions = hub.sessions.list
        let selected = sessions.first { $0.id == selection } ?? sessions.first
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SpendTrend(spend: hub.spend)
                    Spacer(minLength: 0)
                    AgentHistoryButton(showing: $showingHistory)
                    PrivacyButton(hub: hub)
                }
                LimitsHeader(readings: hub.limitReadings)
                if sessions.isEmpty && CloudLane.visible(cloud.tasks, now: .now).isEmpty {
                    if hub.connected.isEmpty { ConnectAgentsHint(hub: hub) } else { NoSessionsHint() }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(sessions) { session in
                                DetailSessionRow(
                                    session: session, selected: session.id == selected?.id, hidden: hub.detailsHidden
                                )
                                .onTapGesture {
                                    selection = session.id
                                    showingHistory = false
                                }
                            }
                            CloudTasksLane(store: cloud, hidden: hub.detailsHidden)
                        }
                    }
                }
            }
            .frame(width: 190)

            if showingHistory {
                AgentHistoryView(
                    store: model.services.agentHistory, hidden: hub.detailsHidden,
                    enabled: model.services.preferences.agentHistory)
            } else if let selected {
                SessionDetail(
                    session: selected, hub: hub, hidden: hub.detailsHidden, draft: draft(for: selected.id),
                    note: $note, listening: listening(to: selected.id))
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            hub.refreshInstalledIfStale()
            cloud.refreshNow()
        }
        .onChange(of: selected?.id) { note = nil }
        // Dictation types into the draft box on screen; it's hidden while details are private.
        .onChange(of: hub.detailsHidden ? nil : selected?.id, initial: true) { _, session in
            model.draftClaim = DraftBoxClaim.claim(model.draftClaim, owner: owner, session: session)
        }
        .onDisappear { model.draftClaim = DraftBoxClaim.release(model.draftClaim, owner: owner) }
        .onAppear {
            // Opened from the pill: start on that session, once. The window keeps it, so
            // switching sidebar rows comes back to the same session.
            if let focused = model.focusedSession {
                selection = focused
                if host == .notch { model.focusedSession = nil }
            }
        }
        .onChange(of: selection) { _, session in
            if host == .window { model.focusedSession = session }
        }
        .onChange(of: model.focusedSession) { _, session in
            // A pill click while the window already shows Agents.
            if host == .window, let session { selection = session }
        }
    }

    @Environment(\.shelfHost) private var host

    private func listening(to session: String) -> Bool {
        let dictation = model.services.dictation
        return dictation.phase.isActive && dictation.target == .agentDraft(session: session)
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
        let tip =
            hub.hiddenReason.map { "Commands and file names are hidden \($0)" + (locked ? "" : "; click to show") }
            ?? "Hide commands and file names"
        Button {
            hub.hideNow.toggle()
        } label: {
            Image(systemName: hub.detailsHidden ? "eye.slash" : "eye")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hub.detailsHidden ? Color.wispViolet : Color.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .hoverHint(tip, edge: .bottom, help: tip)
        .accessibilityLabel(
            locked
                ? "Agent details hidden \(hub.hiddenReason ?? "")"
                : hub.hideNow ? "Show agent details" : "Hide agent details")
    }
}

/// The title line (project and branch), then the glance lines. A tap selects the session,
/// done or not; the detail pane's terminal button jumps.
private struct DetailSessionRow: View {
    let session: AgentSession
    let selected: Bool
    let hidden: Bool

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
                    .layoutPriority(1)
                if let branch = session.branch {
                    Text(branch).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                SessionGlanceLines(
                    glance: SessionGlance.make(session, now: context.date, hidden: hidden), terminal: session.terminal)
            }
            .padding(.leading, 22)
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
    var listening = false

    @Environment(\.colorScheme) private var colorScheme

    /// White on 30% violet reads in Dark mode but not on a light window, so an empty draft
    /// greys the button there instead.
    private var pasteFill: Color {
        if !draft.isEmpty { return Color.wispViolet.opacity(0.9) }
        return colorScheme == .dark ? Color.wispViolet.opacity(0.3) : Color.ink.opacity(0.08)
    }

    private var pasteText: Color {
        draft.isEmpty && colorScheme == .light ? Color.secondaryText : .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                if let percent = session.contextPercent { ContextBar(percent: percent) }
                Spacer(minLength: 4)
                // Full labels when they fit, icons with tooltips when the panel is narrow,
                // so a label never wraps onto a second line.
                ViewThatFits(in: .horizontal) {
                    actions.labelStyle(.titleAndIcon)
                    actions.labelStyle(.iconOnly)
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
            TextField(listening ? "Listening…" : note ?? "Draft a prompt…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.ink.opacity(0.08)))
                .onSubmit(send)
            Button("Paste in \(TerminalApps.name(for: session.terminal) ?? "Terminal")", action: send)
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(pasteFill))
                .foregroundStyle(pasteText)
                .disabled(draft.isEmpty)
                .help("Pastes into the session's terminal without sending; press Return there")
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            let terminal = TerminalApps.name(for: session.terminal) ?? "Terminal"
            action(terminal, symbol: "arrow.up.forward.app", help: "Show in \(terminal)") {
                hub.focus(session: session.id)
            }
            if !session.cwd.isEmpty {
                action("Folder", symbol: "folder", help: "Open the folder in Finder") {
                    hub.openFolder(session: session.id)
                }
            }
            if session.transcriptPath != nil {
                action("Transcript", symbol: "doc.text", help: "Show the transcript in Finder") {
                    if !hub.revealTranscript(session: session.id) { note = "Transcript not found" }
                }
            }
            // Wisp's clipboard history would show the ID, so it isn't offered while private.
            if !hidden {
                action("Copy ID", symbol: "doc.on.doc", help: "Copy the session ID") {
                    hub.copyID(session: session.id)
                    note = "Session ID copied"
                }
            }
        }
    }

    private func action(
        _ title: String, symbol: String, help: String, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold))
                .lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.project(session.project))
        // The header sits at the top of the shelf, so its labels drop below.
        .hoverHint(help, edge: .bottom, help: help)
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
        case .started, .prompt, .answered: .ink.opacity(0.7)
        case .request, .waiting: .wispAmber
        case .allowed, .done: .wispGreen
        case .denied: .red
        case .compacted: .wispViolet
        }
    }
}
