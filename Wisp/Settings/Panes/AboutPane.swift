import AppKit
import SwiftUI
import WispCore

struct AboutSettings: View {
    let preferences: Preferences

    private static let repository = URL(string: "https://github.com/Maestroharyor/wisp")
    private static let issues = URL(string: "https://github.com/Maestroharyor/wisp/issues/new")
    private static let author = URL(string: "https://ayomideodewale.com")

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
                        Text("Live activities, a file tray and widgets for the Mac notch.")
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
                    if let author = Self.author {
                        Link(destination: author) { Label("ayomideodewale.com", systemImage: "globe") }
                    }
                    if let issues = Self.issues {
                        Link(destination: issues) { Label("Report an issue", systemImage: "ladybug") }
                    }
                }
            }
            Section("Keyboard shortcuts") {
                ShortcutRow(keys: hyper("Space"), action: "Open or close the shelf")
                ShortcutRow(keys: hyper("V"), action: "Clipboard history")
                ShortcutRow(keys: hyper("1–9"), action: "Switch profile")
                ShortcutRow(keys: "Esc", action: "Back to the grid, or close the shelf")
                ShortcutRow(keys: "Right-click the notch", action: "Menu: Customise Home, profiles, Settings")
            }
            Section {
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

    private func hyper(_ key: String) -> String {
        preferences.hotkey.usesHyper ? "⇪ \(key)" : "⇧⌘ \(key)"
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
