import AppKit
import SwiftUI
import WispCore

struct AgentSettings: View {
    let hub: AgentHub
    @Bindable var preferences: Preferences

    /// The week by project; empty when it would only repeat the total as "Other projects".
    private var projectSpend: [DailySpend.ProjectSpend] {
        let rows = hub.spend.byProject(lastDays: 7, ending: .now, top: 5)
        return rows.contains { $0.project != DailySpend.otherProjects } ? rows : []
    }

    var body: some View {
        Form {
            if let source = hub.outdated.sorted(by: { $0.rawValue < $1.rawValue }).first {
                Section {
                    LabeledContent {
                        Button("Update Hooks") { hub.installHooks(source) }
                    } label: {
                        Text("Agents has new features")
                        Text("Update \(source.displayName)'s hooks so the notch gets everything this version shows.")
                    }
                }
            }
            AgentConnection(
                hub: hub, source: .claude,
                about:
                    "Wisp adds hooks to ~/.claude/settings.json, so every Claude Code session shows in the notch: a pill while it works, Done when it finishes, and an Allow or Deny card for permission prompts. Prompts you don't answer within two minutes fall back to the terminal. Restart running sessions after connecting."
            )
            AgentConnection(
                hub: hub, source: .codex,
                about:
                    "Wisp adds hooks to ~/.codex/hooks.json for the same pill, Done and Allow or Deny card. Codex asks you to trust new hooks once: run /hooks in Codex after connecting."
            )
            TerminalBarSettings(hub: hub, preferences: preferences)
            CommandLineSettings()
            Section {
                Toggle(
                    "Show tool activity",
                    isOn: Binding(
                        get: { preferences.agentToolActivity },
                        set: { on in
                            if hub.setToolActivity(on) { preferences.agentToolActivity = on }
                        }))
                if hub.isConnected(.claude), hub.toolsInstalled != preferences.agentToolActivity {
                    Label(
                        "Claude Code's settings don't match this choice. Turn it off and on again to apply it.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Tool activity")
            } footer: {
                Text(
                    "Shows what Claude Code is doing in the notch, such as the command it's running or the file it's editing, and how many other sessions are going. Adds background hooks for tool calls, so they never wait for Wisp. Secrets in commands are masked, the privacy setting below applies, and nothing leaves your Mac."
                        + (hub.isConnected(.claude) ? "" : " Applies when you connect Claude Code.")
                )
            }
            Section("Alerts and spend") {
                Toggle("Play a sound when an agent asks for permission", isOn: $preferences.approvalSound)
                Toggle("Alert when a session's context is nearly full", isOn: $preferences.contextAlert)
                if preferences.contextAlert {
                    Stepper(value: $preferences.contextThreshold, in: 50...95, step: 5) {
                        LabeledContent("Alert at", value: "\(preferences.contextThreshold)%")
                    }
                }
                LabeledContent("Estimated spend today") {
                    Text(String(format: "~$%.2f", hub.spend.total(on: .now))).monospacedDigit()
                }
                LabeledContent("Last 7 days") {
                    Text(String(format: "~$%.2f", hub.spend.total(lastDays: 7, ending: .now))).monospacedDigit()
                }
                ForEach(projectSpend, id: \.project) { project in
                    LabeledContent(project.project) {
                        Text(String(format: "~$%.2f", project.week)).monospacedDigit()
                    }
                    .padding(.leading, 12)
                    .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Hide commands and file names", selection: $preferences.agentPrivacy) {
                    Text("Never").tag(AgentPrivacy.Mode.never)
                    Text("During calls").tag(AgentPrivacy.Mode.duringCalls)
                    Text("Always").tag(AgentPrivacy.Mode.always)
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text(
                    "Hides commands, file paths, session names and prompt drafts in the notch, so they don't show on a shared screen. macOS doesn't tell apps when the screen is shared, so a call app or browser using the microphone counts as a call. The eye button beside today's spend in the Agents widget (Wide size, as in the Code profile) hides them any time."
                )
            }
            let sessions = hub.sessions.list
            if !sessions.isEmpty {
                Section("Sessions") {
                    ForEach(sessions) { session in
                        LabeledContent {
                            HStack(spacing: 8) {
                                if !session.figures.isEmpty {
                                    Text(session.figures).foregroundStyle(.secondary)
                                }
                                Button("Show Terminal") { hub.focus(session: session.id) }.controlSize(.small)
                            }
                        } label: {
                            Label {
                                Text(session.project)
                            } icon: {
                                Image(systemName: session.source.symbol).foregroundStyle(Color.project(session.project))
                            }
                        }
                    }
                }
            }
            if !hub.listening {
                Section {
                    Label("Wisp isn't listening for agents right now.", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { hub.refreshInstalled() }
    }
}

private struct AgentConnection: View {
    let hub: AgentHub
    let source: AgentSource
    let about: String

    var body: some View {
        let connected = hub.isConnected(source)
        let elsewhere = hub.connectedElsewhere.contains(source)
        Section(source.displayName) {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle().fill(connected ? Color.green : elsewhere ? Color.orange : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(connected ? "Connected" : elsewhere ? "Hooks point at another copy of Wisp" : "Not connected")
                }
            }
            if connected {
                Button("Disconnect \(source.displayName)") { hub.removeHooks(source) }
            } else if elsewhere {
                // Its events go to that copy, so this one shows no sessions until switched.
                Button("Use this Wisp") { hub.installHooks(source) }
                Button("Disconnect \(source.displayName)") { hub.removeHooks(source) }
            } else {
                Button("Connect \(source.displayName)") { hub.installHooks(source) }
            }
            Text(about).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Claude Code's status bar: Wisp's, the user's own (Wisp listens through it), or as it was.
private struct TerminalBarSettings: View {
    let hub: AgentHub
    @Bindable var preferences: Preferences

    private static let sample = StatusBarRenderer.Input(
        project: "wisp", branch: "main", contextPercent: 78, model: "Opus", cost: 0.41, linesAdded: 120,
        linesRemoved: 34)

    var body: some View {
        let hasOwnBar = hub.statusLine.userCommand != nil
        Section("Terminal bar") {
            Picker(
                "Claude Code status bar",
                selection: Binding(
                    get: { preferences.terminalBarMode },
                    set: { mode in
                        if hub.setTerminalBar(mode) { preferences.terminalBarMode = mode }
                    })
            ) {
                Text("Wisp's bar").tag(TerminalBarMode.wisp)
                Text(hasOwnBar ? "Keep my bar" : "Listen only").tag(TerminalBarMode.listen)
                Text("Off").tag(TerminalBarMode.off)
            }
            if preferences.terminalBarMode == .wisp { preview }
            if let mismatch = mismatch {
                Label(mismatch, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Text(explanation(hasOwnBar: hasOwnBar)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        StatusBarRenderer.line(Self.sample, columns: nil).reduce(Text("")) { line, span in
            let piece = Text(span.text)
            guard let code = span.color else { return line + piece }
            let rgb = StatusBarRenderer.rgb(code: code)
            return line + piece.foregroundColor(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.85)))
        .foregroundStyle(.white)
        .accessibilityLabel("Preview of Wisp's status bar")
    }

    /// When ~/.claude/settings.json no longer matches the choice (edited by hand, or by
    /// another copy of Wisp), say so rather than showing a choice that isn't in effect.
    private var mismatch: String? {
        guard hub.isConnected(.claude) else { return nil }
        let matches: Bool
        switch (preferences.terminalBarMode, hub.statusLine) {
        case (.wisp, .wisp), (.listen, .listening): matches = true
        case (.off, .none), (.off, .foreign): matches = true
        default: matches = false
        }
        return matches
            ? nil : "Claude Code's settings have a different status bar. Choose an option again to apply it."
    }

    private func explanation(hasOwnBar: Bool) -> String {
        let connect = hub.isConnected(.claude) ? "" : " Applies when you connect Claude Code."
        switch preferences.terminalBarMode {
        case .wisp:
            return
                (hasOwnBar
                ? "Shows under Claude Code's prompt in place of your own bar, which comes back if you choose Off."
                : "Shows under Claude Code's prompt: project, branch, context used, model, cost and lines changed.")
                + " It also sends Wisp the session's live figures." + connect
        case .listen:
            return
                (hasOwnBar
                ? "Your bar stays as it is. Wisp runs it and reads the session's live figures on the way."
                : "Nothing new in the terminal; Wisp still reads the session's live figures.") + connect
        case .off:
            return
                "Claude Code's status bar is left as it was before Wisp, and the notch shows no live cost or context."
                + connect
        }
    }
}

/// Installs `wisp` (status, watch, spend) as a link in ~/.local/bin.
private struct CommandLineSettings: View {
    @State private var installer = CommandLineInstaller()

    var body: some View {
        Section {
            LabeledContent {
                switch installer.state {
                case .installed, .otherApp: Button("Uninstall") { installer.uninstall() }
                case .notInstalled: Button("Install") { installer.install() }
                case .foreign: EmptyView()
                }
            } label: {
                Text("wisp command")
                Text(status)
            }
            if case .otherApp = installer.state {
                Button("Point it at this Wisp") { installer.install() }
            }
            if let problem = installer.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if installer.state == .installed, installer.path == .notOnPath {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "~/.local/bin isn't on your PATH. Add this line to ~/.zshrc:",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    Text(#"export PATH="$HOME/.local/bin:$PATH""#)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
        } header: {
            Text("Command-line tool")
        } footer: {
            Text(
                "Run wisp status, wisp watch or wisp spend in a terminal to see your sessions and spend. Wisp must be running. The privacy setting below applies there too."
                    + (installer.path == .unknown && installer.state == .installed
                        ? " Wisp couldn't check your PATH; if wisp isn't found, add ~/.local/bin to it." : "")
            )
        }
        .onAppear { installer.refresh() }
    }

    private var status: String {
        switch installer.state {
        case .installed: "Installed at ~/.local/bin/wisp"
        case .notInstalled: "Not installed"
        case .otherApp(let path): "Points to \(Self.appName(path))"
        case .foreign: "~/.local/bin/wisp is another program, so Wisp leaves it alone"
        }
    }

    /// "Wisp Dev" or "Wisp", from the app the helper is in; its folder when that's gone.
    private static func appName(_ helper: String) -> String {
        let app = AppSupport.appBundle(containingHelper: URL(fileURLWithPath: helper))
        guard let id = Bundle(url: app)?.bundleIdentifier else { return app.path }
        return id.hasSuffix(".dev") ? "Wisp Dev" : "Wisp"
    }
}
