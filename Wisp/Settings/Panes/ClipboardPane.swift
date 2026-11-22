import AppKit
import SwiftUI
import WispCore

/// The Clipboard pane: history, how much it keeps, and apps it never keeps copies from.
struct ClipboardSettings: View {
    @Bindable var preferences: Preferences
    let store: ClipboardStore
    @State private var confirmingClear = false

    var body: some View {
        Form {
            history
            Section(header: "Length") {
                Stepper(value: $preferences.clipboardLimit, in: 20...1000, step: 20) {
                    LabeledContent("Clipboard keeps up to", value: "\(preferences.clipboardLimit) items")
                }
                .disabled(!preferences.clipboardEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var history: some View {
        Section {
            Toggle("Keep clipboard history", isOn: $preferences.clipboardEnabled)
            Button("Clear history (keeps pinned items)…", role: .destructive) { confirmingClear = true }
                .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
                    Button("Clear history", role: .destructive) { store.clear() }
                } message: {
                    Text("Pinned items are kept.")
                }
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
                            .accessibilityLabel("Remove \(Self.name(of: id))")
                        }
                    }
                    Button("Add app…") { addApp() }
                }
            }
        } header: {
            SettingsHeader("History")
        } footer: {
            Text(
                "Items apps mark as concealed, such as passwords, are never saved, nor is anything copied while one of the apps above is in front. History stays on this Mac."
            )
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
