import AppKit
import SwiftUI
import WispCore

/// The clipboard's part of the Shelf pane. How many items it keeps is under Advanced.
struct ClipboardSection: View {
    @Bindable var preferences: Preferences
    let store: ClipboardStore

    var body: some View {
        Section("Clipboard") {
            Toggle("Keep clipboard history", isOn: $preferences.clipboardEnabled)
            Button("Clear history (keeps pinned items)", role: .destructive) { store.clear() }
            Text(
                "Passwords and other items that apps mark as concealed are never saved. History is stored only on this Mac."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
