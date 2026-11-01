import AppKit
import SwiftUI
import WispCore

struct AboutSettings: View {
    let preferences: Preferences
    @Bindable var updater: Updater
    let runSetup: () -> Void

    private static let repository = URL(string: "https://github.com/Maestroharyor/wisp")
    private static let issues = URL(string: "https://github.com/Maestroharyor/wisp/issues/new")
    private static let author = URL(string: "https://ayomideodewale.com")
    private static let website = URL(string: "https://ayomideodewale.com/wisp")

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wisp").font(.system(size: 18, weight: .bold))
                        Text("Version \(Self.version)").foregroundStyle(.secondary)
                        Text("The notch for people who build.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let author = Self.author {
                            HStack(spacing: 4) {
                                Text("Made by")
                                Link("Ayomide Odewale", destination: author)
                            }
                            .font(.caption)
                            .padding(.top, 2)
                        }
                    }
                    Spacer()
                }
                HStack {
                    if let repository = Self.repository {
                        Link(destination: repository) {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    if let website = Self.website {
                        Link(destination: website) { Label("Website", systemImage: "globe") }
                    }
                    if let issues = Self.issues {
                        Link(destination: issues) { Label("Report an issue", systemImage: "ladybug") }
                    }
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloads)
                    .disabled(!updater.automaticallyChecks)
                LabeledContent("Last checked") {
                    if let lastCheck = updater.lastCheck {
                        Text(lastCheck, format: .relative(presentation: .named))
                    } else {
                        Text("Never")
                    }
                }
                Button("Check Now", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text(
                    "With automatic checks on, Wisp looks at GitHub Releases once a day. Updates are signed, and your settings and permissions are kept."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard shortcuts") {
                ShortcutRow(keys: preferences.hotkey.description, action: "Open or close the shelf")
                // Without Hyper, clipboard history has its own shortcut and profiles have none.
                if preferences.hotkey.usesHyper {
                    ShortcutRow(keys: "⇪ V", action: "Clipboard history")
                    ShortcutRow(keys: "⇪ 1–9", action: "Switch profile")
                } else {
                    ShortcutRow(keys: Hotkey.clipboardFallback.description, action: "Clipboard history")
                }
                ShortcutRow(keys: "Esc", action: "Back to the grid, or close the shelf")
                ShortcutRow(keys: "Right-click the notch", action: "Menu: Customise Home, profiles, Settings")
            }
            Section {
                Button("Run Setup Again", action: runSetup)
                Button("Reset All Settings…", role: .destructive, action: reset)
            } footer: {
                Text(
                    "Puts every Wisp setting back to its default and relaunches Wisp. Your tray, notes, clipboard history and chat logins are kept."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"].map { "\($0)" } ?? "?"
        let build = info?["CFBundleVersion"].map { "\($0)" } ?? "?"
        return "\(short) (\(build))"
    }

    private func reset() {
        let alert = NSAlert()
        alert.messageText = "Reset all Wisp settings?"
        alert.informativeText = "Every setting goes back to its default, and Wisp relaunches."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        preferences.resetAll()
        relaunch()
    }

    /// Starts a fresh copy once this one has quit, so the defaults reload cleanly.
    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        LabeledContent(action) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
        }
    }
}
