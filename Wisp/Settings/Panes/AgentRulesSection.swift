import SwiftUI
import WispCore

/// Claude Code's allow, ask and deny rules: the user's settings and each project with a live
/// session. Allow rules can be removed here; ask and deny are only shown.
struct AgentRulesSection: View {
    let hub: AgentHub

    @State private var files: [AgentHub.RulesFile] = []
    @State private var revealed = false
    @State private var removal: Removal?
    @State private var problem: String?

    private struct Removal: Identifiable {
        var id: String { file.path + "\n" + rule }
        let rule: String
        let file: AgentHub.RulesFile
    }

    /// Changes when a session starts or ends in another folder, to list that project.
    private var folders: [String] { hub.sessions.list.map(\.cwd).sorted() }

    var body: some View {
        Section {
            if hub.detailsHidden && !revealed {
                HStack {
                    Label("Rules are hidden while agent details are private", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show") { revealed = true }
                }
            } else {
                ForEach(files) { file in
                    fileRows(file)
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Rules")
        } footer: {
            Text(
                "Always allow… on a Claude Code request saves a rule in Claude Code's settings. Claude Code checks deny rules first, then ask, then allow. Change ask and deny rules in the files themselves."
            )
        }
        .task(id: folders) { reload() }
        .confirmationDialog(
            "Remove this rule?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
            presenting: removal
        ) { item in
            Button("Remove", role: .destructive) { remove(item) }
        } message: { item in
            Text(
                item.file.scope.keepsCopies
                    ? "Claude Code will ask again for \(item.rule). The current file is saved next to it with .wisp-previous on the end."
                    : "Claude Code will ask again for \(item.rule)."
            )
        }
    }

    @ViewBuilder private func fileRows(_ file: AgentHub.RulesFile) -> some View {
        LabeledContent {
            Text(file.displayPath).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                .truncationMode(.middle).textSelection(.enabled)
        } label: {
            Text(file.title).fontWeight(.semibold)
        }
        if let problem = file.problem {
            Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        } else if file.lists.isEmpty {
            Text("No rules").font(.caption).foregroundStyle(.secondary).padding(.leading, 12)
        } else {
            ForEach(file.lists.allow, id: \.self) { rule in
                ruleRow(rule, kind: "Allow") {
                    Button("Remove") { removal = Removal(rule: rule, file: file) }.controlSize(.small)
                }
            }
            ForEach(file.lists.ask, id: \.self) { rule in ruleRow(rule, kind: "Ask") { EmptyView() } }
            ForEach(file.lists.deny, id: \.self) { rule in ruleRow(rule, kind: "Deny") { EmptyView() } }
        }
    }

    private func ruleRow(_ rule: String, kind: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(kind)
                .font(.caption.weight(.semibold))
                .foregroundStyle(kind == "Allow" ? Color.wispViolet : Color.secondary)
                .frame(width: 40, alignment: .leading)
            Text(rule).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            action()
        }
        .padding(.leading, 12)
    }

    private func reload() {
        files = hub.rulesFiles()
    }

    private func remove(_ item: Removal) {
        do {
            try hub.removeRule(item.rule, from: item.file)
            problem = nil
        } catch {
            problem = AgentHub.rulesProblem(error, path: item.file.path)
        }
        reload()
    }
}
