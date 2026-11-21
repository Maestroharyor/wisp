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
            LabeledContent("Never keep copies from") {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(preferences.clipboardExcludedApps, id: \.self) { id in
                        HStack(spacing: 6) {
                            Text(Self.name(of: id)).lineLimit(1)
                            Button {
                                preferences.clipboardExcludedApps.removeAll { $0 == id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Keep copies from this app again")
                        }
                    }
                    Button("Add app…") { addApp() }
                }
            }
            Text(
                "Passwords and other items that apps mark as concealed are never saved, and neither is anything copied while one of the apps above is in front. History is stored only on this Mac."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
            !preferences.clipboardExcludedApps.contains(id)
        else { return }
        preferences.clipboardExcludedApps.append(id)
    }

    /// The app's name, or its bundle id when it isn't installed.
    private static func name(of id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        let shown = FileManager.default.displayName(atPath: url.path)
        return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
    }
}
