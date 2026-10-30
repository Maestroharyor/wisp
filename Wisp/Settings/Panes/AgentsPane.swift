import AppKit
import SwiftUI
import WispCore

struct AgentSettings: View {
    let hub: AgentHub
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
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
            Section("Alerts and spend") {
                Toggle("Play a sound when an agent asks for permission", isOn: $preferences.approvalSound)
                LabeledContent("Estimated spend today") {
                    Text(String(format: "~$%.2f", hub.spend.total(on: .now))).monospacedDigit()
                }
            }
            let sessions = hub.sessions.list
            if !sessions.isEmpty {
                Section("Sessions") {
                    ForEach(sessions) { session in
                        LabeledContent {
                            HStack(spacing: 8) {
                                if let usage = session.usage {
                                    Text(usage.summary(cost: session.cost)).foregroundStyle(.secondary)
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
        Section(source.displayName) {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle().fill(connected ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Text(connected ? "Connected" : "Not connected")
                }
            }
            if connected {
                Button("Disconnect \(source.displayName)") { hub.removeHooks(source) }
            } else {
                Button("Connect \(source.displayName)") { hub.installHooks(source) }
            }
            Text(about).font(.caption).foregroundStyle(.secondary)
        }
    }
}
