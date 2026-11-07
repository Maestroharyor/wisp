import SwiftUI
import WispCore

/// The Agents widget's Cloud lane: cloud agent tasks that are working or finished in the last
/// day. Click a row to open it on the web; its menu opens the pull request or applies a
/// finished Codex task to a checkout.
struct CloudTasksLane: View {
    let store: CloudAgentStore
    let hidden: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            let shown = CloudLane.visible(store.tasks, now: context.date)
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    ForEach(shown) { task in
                        CloudTaskRow(task: task, hidden: hidden, applying: store.applying == task.id)
                            .onTapGesture { store.open(task) }
                            .contextMenu { menu(for: task) }
                            .help("Open on the web")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for task: CloudTask) -> some View {
        if task.url != nil { Button("Open task") { store.open(task) } }
        if task.pullRequest != nil { Button("Open pull request") { store.openPullRequest(task) } }
        if task.canApply {
            Button("Apply to a checkout…") { store.applyCodexTask(task) }.disabled(store.applying != nil)
        }
    }
}

private struct CloudTaskRow: View {
    let task: CloudTask
    let hidden: Bool
    let applying: Bool

    @State private var hovering = false

    /// The title is often the prompt, so private mode shows the source and repository instead.
    private var title: String {
        if hidden || task.title.isEmpty { return "\(task.source.displayName) task" }
        return task.title
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: task.source.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let repository = task.repository, !hidden {
                    Text(repository)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if let checks = task.checks { ChecksBadge(checks: checks) }
            if applying {
                ProgressView().controlSize(.mini)
            } else {
                Text(task.status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.ink.opacity(hovering ? 0.12 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var tint: Color {
        switch task.status {
        case .queued, .running, .waiting: .wispViolet
        case .ready: .wispGreen
        case .failed: .red.opacity(0.85)
        case .cancelled: .secondaryText
        }
    }
}

/// A pull request's CI at a glance: a tick, a cross, or a clock while checks run.
private struct ChecksBadge: View {
    let checks: CloudChecks

    var body: some View {
        let (symbol, tint, label): (String, Color, String) =
            switch checks.state {
            case .passing: ("checkmark.seal.fill", .wispGreen, "Checks passed")
            case .pending: ("clock.fill", .wispViolet, "Checks running")
            case .failing: ("xmark.seal.fill", .red.opacity(0.85), "\(checks.failed) checks failed")
            }
        Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .help(label)
            .accessibilityLabel(label)
    }
}
