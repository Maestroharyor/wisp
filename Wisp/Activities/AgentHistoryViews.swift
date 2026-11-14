import SwiftUI
import WispCore

/// Finished sessions with search, in the Agents widget's details. Files, commands and summaries
/// are hidden, and left out of the search, while agent details are private.
struct AgentHistoryView: View {
    let store: AgentHistoryStore
    let hidden: Bool
    /// Settings › Agents › Keep session history.
    let enabled: Bool

    @State private var query = ""
    @State private var expanded: String?
    @State private var tab = Tab.sessions

    private enum Tab: Hashable {
        case sessions, approvals, activity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("History", selection: $tab) {
                Text("Sessions").tag(Tab.sessions)
                Text("Approvals").tag(Tab.approvals)
                Text("Activity").tag(Tab.activity)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            switch tab {
            case .sessions: sessions
            case .approvals: ApprovalHistoryList(log: store.approvals, hidden: hidden, enabled: enabled)
            case .activity: activity
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var activity: some View {
        let map = store.history.activityMap()
        if map.isEmpty {
            Text(enabled ? "Days with agent sessions show here" : "Session history is off in Settings › Agents")
                .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ActivityMapView(map: map).equatable()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sessions: some View {
        let records = store.history.search(query, hidden: hidden)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.ink.opacity(0.08)))

            if records.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(records) { record in
                            HistoryRow(record: record, hidden: hidden, expanded: expanded == record.id)
                                .onTapGesture { expanded = expanded == record.id ? nil : record.id }
                                .contextMenu {
                                    Button("Remove from history") { store.remove(record.id) }
                                }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyText: String {
        if !query.isEmpty { return "Nothing matches" }
        return enabled ? "Finished sessions show here" : "Session history is off in Settings › Agents"
    }
}

/// One finished session: project, when and how long, figures, and the summary. A tap shows
/// its tools, tests, files and commands.
private struct HistoryRow: View {
    let record: SessionRecord
    let hidden: Bool
    let expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: record.source.symbol).font(.system(size: 11))
                    .foregroundStyle(Color.project(record.project))
                Text(record.project).font(.system(size: 12, weight: .semibold)).lineLimit(1).layoutPriority(1)
                if let branch = record.branch {
                    Text(branch).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(record.ended, format: .relative(presentation: .named))
                    .font(.system(size: 10)).foregroundStyle(Color.secondaryText).lineLimit(1).fixedSize()
            }
            Text(figures).font(.system(size: 10)).monospacedDigit().foregroundStyle(Color.secondaryText).lineLimit(1)
            if let summary = record.summary {
                Text(hidden ? "Summary hidden while details are private" : summary)
                    .font(.system(size: 11))
                    .foregroundStyle(hidden ? Color.secondaryText : Color.ink)
                    .lineLimit(expanded ? nil : 2)
                    .textSelection(.enabled)
            }
            if expanded { details }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.project(record.project).opacity(expanded ? 0.22 : 0.1))
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Hides the details" : "Shows the details")
    }

    /// "Claude Code · Opus · 12m · ~$0.41 · +120 −34 · 3 prompts".
    private var figures: String {
        var parts = [record.source.displayName]
        if let model = record.model { parts.append(model) }
        parts.append(DurationText.text(for: record.duration))
        if let cost = record.cost { parts.append((record.costIsReal ? "" : "~") + String(format: "$%.2f", cost)) }
        if record.linesAdded > 0 || record.linesRemoved > 0 {
            parts.append("+\(record.linesAdded) −\(record.linesRemoved)")
        }
        parts.append("\(record.turns) prompt\(record.turns == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
            if !record.tools.isEmpty {
                row("Tools", record.toolsByUse.prefix(6).map { "\($0.name) \($0.count)" }.joined(separator: ", "))
            }
            if !record.tests.isEmpty {
                GridRow {
                    Text("Tests").foregroundStyle(Color.secondaryText)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(record.tests.enumerated()), id: \.offset) { _, run in
                            Label {
                                Text("\(hidden ? "Tests" : run.command) \(run.outcome.phrase)").lineLimit(1)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(systemName: run.outcome.symbol).foregroundStyle(run.outcome.tint)
                            }
                        }
                    }
                }
            }
            if !record.files.isEmpty {
                row("Files", hidden ? AgentPrivacy.placeholder : record.files.joined(separator: ", "))
            }
            if !record.commands.isEmpty {
                row("Commands", hidden ? AgentPrivacy.placeholder : record.commands.joined(separator: "\n"))
            }
            if record.requests > 0 { row("Requests", "\(record.requests)") }
            if record.questions > 0 { row("Questions", "\(record.questions)") }
            if record.endedWaiting { row("Ended", "Waiting for you") }
            if record.tools.isEmpty {
                GridRow {
                    Text("Tools").foregroundStyle(Color.secondaryText)
                    Text(
                        "Turn on Show what agents are doing in Settings › Agents › Advanced to keep tools, files, commands and tests"
                    )
                    .foregroundStyle(Color.secondaryText).lineLimit(3)
                }
            }
        }
        .font(.system(size: 10))
        .padding(.top, 2)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Color.secondaryText)
            Text(value).textSelection(.enabled).lineLimit(6).truncationMode(.middle)
        }
    }
}

extension TestOutcome {
    fileprivate var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .notPassed: "xmark.circle.fill"
        case .ran: "circle.dashed"
        case .unknown: "questionmark.circle"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .passed: .wispGreen
        case .notPassed: .red
        case .ran, .unknown: .secondaryText
        }
    }
}

/// Switches the details pane between the selected session and the history.
struct AgentHistoryButton: View {
    @Binding var showing: Bool

    var body: some View {
        let tip = showing ? "Back to live sessions" : "Session history"
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(showing ? Color.wispViolet : Color.secondaryText)
        }
        .buttonStyle(.plain)
        .hoverHint(tip, edge: .bottom, help: tip)
        .accessibilityLabel(tip)
    }
}

/// The last week of requests with how each ended, filtered by session and outcome.
struct ApprovalHistoryList: View {
    let log: ApprovalLog
    let hidden: Bool
    let enabled: Bool

    @State private var session: String?
    @State private var outcome: ApprovalOutcome?

    var body: some View {
        let records = log.filtered(session: session, outcome: outcome)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("Session", selection: $session) {
                    Text("All sessions").tag(String?.none)
                    ForEach(log.sessions, id: \.id) { item in
                        Text(item.project).tag(String?.some(item.id))
                    }
                }
                Picker("Outcome", selection: $outcome) {
                    Text("Any outcome").tag(ApprovalOutcome?.none)
                    ForEach(ApprovalOutcome.allCases, id: \.self) { item in
                        Text(item.title).tag(ApprovalOutcome?.some(item))
                    }
                }
            }
            .labelsHidden()
            .controlSize(.small)
            if records.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(records) { record in
                            ApprovalHistoryRow(record: record, hidden: hidden, showsProject: session == nil)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyText: String {
        if session != nil || outcome != nil { return "Nothing matches" }
        return enabled ? "Requests from the last 7 days show here" : "Session history is off in Settings › Agents"
    }
}

/// One request: what it was, how it ended and when. The summary stays hidden while details are.
struct ApprovalHistoryRow: View {
    let record: ApprovalRecord
    let hidden: Bool
    var showsProject = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: record.outcome.symbol).font(.system(size: 10))
                .foregroundStyle(record.outcome.tint).frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(record.tool).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if showsProject {
                        Text(record.project).font(.system(size: 10)).foregroundStyle(Color.project(record.project))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(record.date, format: .relative(presentation: .named))
                        .font(.system(size: 10)).foregroundStyle(Color.secondaryText).lineLimit(1).fixedSize()
                }
                Text(line).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Answered in the terminal · npm test", the summary left out while hidden.
    private var line: String {
        guard let summary = record.summary, !hidden else { return record.outcome.title }
        return "\(record.outcome.title) · \(summary)"
    }
}

extension ApprovalOutcome {
    var symbol: String {
        switch self {
        case .allowed: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .answered: "arrowshape.turn.up.left.fill"
        case .terminal: "terminal"
        case .rule: "checkmark.shield.fill"
        case .timedOut: "hourglass"
        }
    }

    var tint: Color {
        switch self {
        case .allowed, .rule: .wispGreen
        case .denied: .red
        case .answered: .wispViolet
        case .terminal, .timedOut: .secondaryText
        }
    }
}
