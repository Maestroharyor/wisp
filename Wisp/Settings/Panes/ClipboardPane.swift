import AppKit
import SwiftUI
import WispCore

struct ClipboardSettings: View {
    @Bindable var preferences: Preferences
    let store: ClipboardStore

    var body: some View {
        Form {
            Section("History") {
                Toggle("Keep clipboard history", isOn: $preferences.clipboardEnabled)
                Stepper(value: $preferences.clipboardLimit, in: 20...1000, step: 20) {
                    LabeledContent("Keep up to", value: "\(preferences.clipboardLimit) items")
                }
                Button("Clear History (keeps pinned items)", role: .destructive) { store.clear() }
            }
            Section {
                Text(
                    "Passwords and other items that apps mark as concealed are never saved. History is stored only on this Mac."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
