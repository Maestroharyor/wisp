import AppKit
import SwiftUI
import WispCore

struct AgentSettings: View {
    let hub: AgentHub

    var body: some View {
        Form {
            Section("Claude Code") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(hub.hooksInstalled ? Color.green : Color.secondary).frame(width: 8, height: 8)
                        Text(hub.hooksInstalled ? "Connected" : "Not connected")
                    }
                }
                if hub.hooksInstalled {
                    Button("Disconnect Claude Code") { hub.removeHooks() }
                } else {
                    Button("Connect Claude Code") { hub.installHooks() }
                }
                Text(
                    "Wisp adds hooks to ~/.claude/settings.json, so every Claude Code session shows in the notch: a pill while it works, Done when it finishes, and an Allow or Deny card for permission prompts. Prompts you don't answer within two minutes fall back to the terminal. Restart running sessions after connecting."
                )
                .font(.caption).foregroundStyle(.secondary)
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
