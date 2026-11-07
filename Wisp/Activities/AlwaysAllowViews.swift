import AppKit
import SwiftUI
import WispCore

/// A menu beside Allow All with "Always allow…", kept small so the card's buttons stay as
/// they were.
struct AlwaysAllowMenu: View {
    let approval: AgentApproval
    let hub: AgentHub

    var body: some View {
        Menu {
            Button("Always allow…") { AlwaysAllowWindow.shared.show(approval: approval, hub: hub) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.ink.opacity(0.14)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverHint("Always allow…", help: "Always allow…")
        .accessibilityLabel("More ways to allow")
    }
}

/// The confirm window for "Always allow…": a window of its own, since the notch can't host
/// a sheet and the rule needs a real text field.
@MainActor
final class AlwaysAllowWindow {
    static let shared = AlwaysAllowWindow()

    private var window: NSWindow?

    func show(approval: AgentApproval, hub: AgentHub) {
        let window = window ?? makeWindow()
        self.window = window
        let view = AlwaysAllowSheet(
            approval: approval, hub: hub, hidden: hub.detailsHidden, close: { [weak self] in self?.close() })
        window.contentViewController = NSHostingController(rootView: view)
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered,
            defer: true)
        window.title = "Always allow"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Above other apps, since it opens from the notch while another app is in front.
        window.level = .floating
        return window
    }
}

/// The rule (editable, one per line), where it's saved, and Confirm. In private mode the
/// rule and the project path stay hidden until Show, and Confirm waits for it, so nothing is
/// saved unseen.
private struct AlwaysAllowSheet: View {
    let approval: AgentApproval
    let hub: AgentHub
    let close: () -> Void

    @State private var text: String
    @State private var scope: RuleScope
    @State private var revealed: Bool
    @State private var problem: String?
    @FocusState private var editing: Bool

    init(approval: AgentApproval, hub: AgentHub, hidden: Bool, close: @escaping () -> Void) {
        self.approval = approval
        self.hub = hub
        self.close = close
        let scope: RuleScope = approval.cwd.isEmpty ? .everywhere : .project
        _text = State(initialValue: Self.suggestion(approval, scope: scope))
        _scope = State(initialValue: scope)
        _revealed = State(initialValue: !hidden)
    }

    private var rules: [String] { PermissionRule.rules(in: text) }

    /// The suggested rules for a scope. User settings apply in every project, so their file
    /// rules name this project's folder instead of a relative one.
    private static func suggestion(_ approval: AgentApproval, scope: RuleScope) -> String {
        let rules = scope == .everywhere ? PermissionRule.anchored(approval.rules, cwd: approval.cwd) : approval.rules
        return rules.joined(separator: "\n")
    }
    private var path: String? { AgentHub.rulesPath(scope, cwd: approval.cwd) }
    /// The request can be answered by then (in the terminal, or timed out); the rule still saves.
    private var stillWaiting: Bool { hub.approvals.contains { $0.id == approval.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Always allow").font(.title3.bold())
            Text(
                "Claude Code runs matching requests without asking. The rule is saved in Claude Code's settings, so it works even when Wisp isn't running."
            )
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if revealed {
                ruleEditor
            } else {
                HStack(spacing: 8) {
                    Label("Details hidden", systemImage: "eye.slash").foregroundStyle(.secondary)
                    Button("Show") { revealed = true }
                }
            }
            if !approval.cwd.isEmpty {
                Picker("Save to", selection: $scope) {
                    Text("This project").tag(RuleScope.project)
                    Text("Everywhere").tag(RuleScope.everywhere)
                }
                .pickerStyle(.segmented)
            }
            if let path {
                // A project's path names its folder, which private mode hides.
                Text(revealed || scope == .everywhere ? (path as NSString).abbreviatingWithTildeInPath : "Hidden")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1).truncationMode(.middle)
            }
            if let message = problem ?? (revealed ? PermissionRule.problem(in: rules) : nil) {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if !stillWaiting {
                Text("This request was already answered. The rule applies from the next one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Confirm", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!revealed || PermissionRule.problem(in: rules) != nil)
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 460)
        .tint(.wispViolet)
        .onChange(of: text) { problem = nil }
        .onChange(of: scope) { old, new in
            problem = nil
            // Follow the scope unless the user has edited the rule.
            if text == Self.suggestion(approval, scope: old) { text = Self.suggestion(approval, scope: new) }
        }
    }

    private var ruleEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($editing)
                .padding(6)
                .frame(height: 76)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
            Text("One rule per line. Edit it to allow more or less.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { editing = true }
    }

    private func confirm() {
        do {
            try hub.alwaysAllow(approval, rules: rules, scope: scope)
            close()
        } catch {
            problem = AgentHub.rulesProblem(error, path: path ?? "")
        }
    }
}
