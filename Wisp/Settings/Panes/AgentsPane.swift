import AppKit
import SwiftUI
import WispCore

struct AgentSettings: View {
    let hub: AgentHub
    let cloud: CloudAgentStore
    let history: AgentHistoryStore
    let push: PushService
    @Bindable var preferences: Preferences

    /// "~$12.40", or "~$12.40 of $20" with the budget on.
    private var spentToday: String {
        let spent = String(format: "~$%.2f", hub.spend.total(on: .now))
        guard preferences.budgetAlert else { return spent }
        return "\(spent) of \(SpendBudget.amount(preferences.dailyBudget))"
    }

    /// Ignores zero and negative amounts, which would leave nothing to measure against.
    private var budget: Binding<Double> {
        Binding(
            get: { preferences.dailyBudget },
            set: { if $0 > 0 { preferences.dailyBudget = $0 } })
    }

    var body: some View {
        Form {
            if !hub.listening {
                Section {
                    Label("Wisp isn't listening for agents right now.", systemImage: "exclamationmark.triangle")
                }
            }
            if let source = hub.outdated.sorted(by: { $0.rawValue < $1.rawValue }).first {
                Section {
                    LabeledContent {
                        Button("Update Hooks") { hub.installHooks(source) }
                    } label: {
                        if hub.waitMismatched.contains(source) {
                            Text("Approval wait changed")
                            Text("Update \(source.displayName)'s hooks so permission prompts wait the new time.")
                        } else {
                            Text("Agents has new features")
                            Text(
                                "Update \(source.displayName)'s hooks so the notch gets everything this version shows.")
                        }
                    }
                }
            }
            ForEach(AgentAdapters.all, id: \.source) { adapter in
                AgentConnection(hub: hub, adapter: adapter)
            }
            alerts
            Section("Spend") {
                LabeledContent("Estimated spend today") {
                    Text(spentToday).monospacedDigit()
                }
                LabeledContent("Last 7 days") {
                    Text(String(format: "~$%.2f", hub.spend.total(lastDays: 7, ending: .now))).monospacedDigit()
                }
            }
            PhoneAlertsSection(push: push, hub: hub, preferences: preferences)
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
            Section("Power") {
                Toggle("Keep the Mac awake while an agent works", isOn: $preferences.agentKeepAwake)
                Text("The display can still sleep. Sessions waiting on you don't keep it awake.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            historySection
            CloudAgentsSection(cloud: cloud, preferences: preferences)
            AgentRulesSection(hub: hub)
            AdvancedSection {
                StatusLineSettings(hub: hub, preferences: preferences)
                toolActivity
                CommandLineSettings()
                if preferences.pushEnabled {
                    PhoneAlertsAdvanced(push: push, hub: hub, preferences: preferences)
                } else {
                    // Keeps a search for the server, tokens or wait landing on something.
                    Text("Turn on Phone alerts to set the server, tokens and wait.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { hub.refreshInstalled() }
    }

    private var alerts: some View {
        Section("Alerts") {
            Toggle("Play a sound when an agent asks for permission", isOn: $preferences.approvalSound)
            Toggle("Alert when a session's context reaches the warn level", isOn: $preferences.contextAlert)
            ContextThresholdSlider(
                title: "Warn at", tint: .wispAmber, percent: $preferences.contextWarnPercent,
                range: ContextUsage.Thresholds.warnRange
            ) { warn in
                // Critical stays above warn.
                let lowest = Int(ContextUsage.Thresholds(warn: Double(warn), critical: 0).critical)
                if preferences.contextCriticalPercent < lowest { preferences.contextCriticalPercent = lowest }
            }
            ContextThresholdSlider(
                title: "Critical at", tint: .red, percent: $preferences.contextCriticalPercent,
                range: min(Double(preferences.contextWarnPercent) + ContextUsage.Thresholds.gap, 95)...100
            ) { _ in }
            Text("The context ring turns amber at Warn at and red at Critical at.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Alert when a tool runs long", isOn: $preferences.toolAlert)
                .disabled(!preferences.agentToolActivity)
            if preferences.toolAlert {
                Stepper(value: $preferences.toolAlertMinutes, in: 1...60) {
                    LabeledContent("Alert after", value: "\(preferences.toolAlertMinutes) min")
                }
                .disabled(!preferences.agentToolActivity)
            }
            if !preferences.agentToolActivity {
                Text("Needs Show what agents are doing, under Advanced.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Remind me when a session is still waiting", isOn: $preferences.nudgeAlert)
            if preferences.nudgeAlert {
                Stepper(value: $preferences.nudgeMinutes, in: 1...30) {
                    LabeledContent("Remind after", value: "\(preferences.nudgeMinutes) min")
                }
            }
            Toggle("Alert at 80% and 95% of a Claude usage limit", isOn: $preferences.limitAlert)
            Toggle("Alert at 80% and 100% of a daily budget", isOn: $preferences.budgetAlert)
            if preferences.budgetAlert {
                // Spend is shown in dollars everywhere, whatever the region's currency.
                LabeledContent("Daily budget") {
                    HStack(spacing: 2) {
                        Text("$")
                        TextField("Daily budget", value: budget, format: .number.precision(.fractionLength(0...2)))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        Section {
            Toggle("Keep session history", isOn: $preferences.agentHistory)
            Toggle("Summarise finished sessions with AI", isOn: $preferences.agentSummaries)
                .disabled(!preferences.aiEnabled)
            LabeledContent {
                Button("Clear history") { history.clear() }
                    .disabled(history.history.records.isEmpty)
            } label: {
                let count = history.history.records.count
                Text(count == 1 ? "1 session saved" : "\(count) sessions saved")
            }
        } header: {
            Text("History")
        } footer: {
            Text(
                "Keeps finished sessions on this Mac for 30 days (at most \(SessionHistory.limit)): project, agent, length, cost, tool counts, test results, file names and commands with secrets masked. Tools, files, commands and tests need Show what agents are doing, under Advanced (Copilot CLI sends finished tool calls anyway). Prompts, messages, file contents and command output are never saved. Commands and file names aren't saved while agent details are hidden. Turning history off stops saving; what's saved stays until you clear it. Summaries need AI (Settings › AI), run on this Mac and appear after Done, and in the Done phone alert with Add the command or file name on. Open the history with the clock button in the Agents widget (Wide size)."
            )
        }
    }

    @ViewBuilder private var toolActivity: some View {
        Toggle(
            "Show what agents are doing",
            isOn: Binding(
                get: { preferences.agentToolActivity },
                set: { on in
                    if hub.setToolActivity(on) { preferences.agentToolActivity = on }
                }))
        let mismatched = hub.toolHooksMismatched(wanted: preferences.agentToolActivity)
        if !mismatched.isEmpty {
            let names = ListFormatter.localizedString(byJoining: mismatched.map(\.displayName))
            Label(
                "\(names) hooks don't match this choice. Turn it off and on again to apply it.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption).foregroundStyle(.orange)
        }
        Text(
            "Shows the command an agent is running or the file it's editing in the notch, and how many other sessions are going. Adds hooks for tool calls that never wait for Wisp. Secrets in commands are masked, the privacy setting applies, and nothing leaves your Mac."
                + (hub.isConnected(.claude) ? "" : " Applies when you connect Claude Code.")
        )
        .font(.caption).foregroundStyle(.secondary)
    }
}

private struct AgentConnection: View {
    let hub: AgentHub
    let adapter: AgentAdapter

    private var source: AgentSource { adapter.source }

    /// What connecting does, built from what the adapter can do.
    private var about: String {
        let card =
            adapter.capabilities.contains(.approve)
            ? ", and an Allow or Deny card for permission prompts. Prompts you don't answer within two minutes fall back to the terminal."
            : ". Permission prompts stay in the terminal."
        let note = adapter.setupNote.map { " " + $0 } ?? ""
        if adapter.hookFile.format.isPlugin {
            return
                "Wisp adds a plugin at \(adapter.hookFile.displayPath), so every \(adapter.displayName) session shows in the notch: a pill while it works, Done when it finishes, and an Allow or Deny card for permission prompts, which you can also answer in \(adapter.displayName). Restart \(adapter.displayName) after connecting.\(note)"
        }
        return
            "Wisp adds hooks to \(adapter.hookFile.displayPath), so every \(adapter.displayName) session shows in the notch: a pill while it works, Done when it finishes\(card) Restart running sessions after connecting.\(note)"
    }

    var body: some View {
        let connected = hub.isConnected(source)
        let elsewhere = hub.connectedElsewhere.contains(source)
        Section {
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
        } header: {
            HStack(spacing: 6) {
                Text(adapter.displayName)
                if !adapter.capabilities.contains(.approve) {
                    Text("Monitor only")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .help("Wisp shows this agent's sessions; approve its requests in the terminal.")
                }
            }
        }
    }
}

/// The status line under Claude Code's prompt: Wisp's, the user's own (Wisp listens through
/// it), or as it was. Rows for the Advanced disclosure.
private struct StatusLineSettings: View {
    let hub: AgentHub
    @Bindable var preferences: Preferences

    private static let sample = StatusBarRenderer.Input(
        project: "wisp", branch: "main", contextPercent: 78, model: "Opus", cost: 0.41, linesAdded: 120,
        linesRemoved: 34)

    var body: some View {
        let hasOwnBar = hub.statusLine.userCommand != nil
        Group {
            Picker(
                "Status line under Claude Code's prompt",
                selection: Binding(
                    get: { preferences.terminalBarMode },
                    set: { mode in
                        if hub.setTerminalBar(mode) { preferences.terminalBarMode = mode }
                    })
            ) {
                Text("Wisp's").tag(TerminalBarMode.wisp)
                // Without a status line of the user's own there is nothing to keep, only figures to read.
                Text(hasOwnBar ? "Keep mine" : "Listen only").tag(TerminalBarMode.listen)
                Text("None").tag(TerminalBarMode.off)
            }
            if preferences.terminalBarMode == .wisp { preview }
            if let mismatch = mismatch {
                Label(mismatch, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Text(explanation(hasOwnBar: hasOwnBar)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        var sample = Self.sample
        sample.thresholds = preferences.contextThresholds
        return StatusBarRenderer.line(sample, columns: nil).reduce(Text("")) { line, span in
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
        .accessibilityLabel("Preview of Wisp's status line")
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
            ? nil : "Claude Code's settings have a different status line. Choose an option again to apply it."
    }

    private func explanation(hasOwnBar: Bool) -> String {
        let connect = hub.isConnected(.claude) ? "" : " Applies when you connect Claude Code."
        switch preferences.terminalBarMode {
        case .wisp:
            return
                (hasOwnBar
                ? "Wisp's line shows in place of your own, which comes back if you choose None."
                : "Shows the project, branch, context used, model, cost and lines changed.")
                + " It also sends Wisp the session's live figures." + connect
        case .listen:
            return
                (hasOwnBar
                ? "Your line stays as it is. Wisp runs it and reads the session's live figures on the way."
                : "Nothing new in the terminal; Wisp still reads the session's live figures.") + connect
        case .off:
            return
                "Claude Code's status line is left as it was before Wisp, and the notch shows no live cost or context."
                + connect
        }
    }
}

/// Installs `wisp` (status, watch, spend) as a link in ~/.local/bin. Rows for the Advanced
/// disclosure.
private struct CommandLineSettings: View {
    private let installer = CommandLineInstaller.shared

    var body: some View {
        Group {
            LabeledContent {
                switch installer.state {
                case .installed: Button("Uninstall") { installer.uninstall() }
                // That link belongs to the other copy of Wisp, so it's repointed, never removed from here.
                case .otherApp: Button("Point it at this Wisp") { installer.install() }
                case .notInstalled: Button("Install") { installer.install() }
                case .foreign: EmptyView()
                }
            } label: {
                Text("Command-line tool")
                Text(status)
            }
            .onAppear { installer.refresh() }
            if let problem = installer.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if installer.state == .installed, installer.path == .notOnPath {
                let advice = CommandLineTool.pathAdvice(shell: ProcessInfo.processInfo.environment["SHELL"])
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "~/.local/bin isn't on your PATH. Add this line to \(advice.file), then open a new terminal:",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    HStack {
                        Text(advice.line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Check again") { installer.checkPathAgain() }
                    }
                }
                .font(.caption)
            }
            Text(
                "Run wisp status, wisp watch or wisp spend in a terminal to see your sessions and spend. Wisp must be running. The privacy setting applies there too."
                    + (installer.path == .unknown && installer.state == .installed
                        ? " Wisp couldn't check your PATH; if wisp isn't found, add ~/.local/bin to it." : "")
            )
            .font(.caption).foregroundStyle(.secondary)
        }
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

/// A percentage slider in steps of 5 for one context level, with a dot in that level's colour.
private struct ContextThresholdSlider: View {
    let title: String
    let tint: Color
    @Binding var percent: Int
    let range: ClosedRange<Double>
    let changed: (Int) -> Void

    var body: some View {
        LabeledContent {
            HStack {
                Slider(
                    value: Binding(get: { Double(percent) }, set: { percent = Int($0.rounded()) }), in: range, step: 5
                )
                .frame(width: 160)
                .onChange(of: percent) { _, new in changed(new) }
                Text("\(percent)%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Circle().fill(tint).frame(width: 8, height: 8)
            }
        }
    }
}
