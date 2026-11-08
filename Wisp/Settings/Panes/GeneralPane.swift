import AppKit
import SwiftUI
import WispCore

struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let hotkeys: HotkeyCenter
    let dictation: DictationEngine
    let accent: Color
    let glow: Color
    let missing: [Permission]
    let fixPermissions: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                NotchPreview(preferences: preferences, accent: accent, glow: glow)
                if !missing.isEmpty {
                    HealthBanner(missing: missing, fix: fixPermissions)
                }
            }
            Section("Shortcut") {
                Toggle("Open the shelf with Caps Lock + Space", isOn: usesCapsLock)
                if !preferences.hotkey.usesHyper {
                    LabeledContent("Shortcut") {
                        HotkeyRecorder(hotkey: $preferences.hotkey)
                    }
                }
                LabeledContent("Status") {
                    HStack {
                        Text(hotkeys.status.message).foregroundStyle(.secondary)
                        if hotkeys.status == .needsAccessibility {
                            Button("Open Accessibility Settings", action: AccessibilityPermission.openSettings)
                        }
                    }
                }
            }

            Section("Keyboard shortcuts") {
                ShortcutRow(keys: preferences.hotkey.description, action: "Open or close the shelf")
                // Without Hyper, clipboard history has its own shortcut and profiles have none.
                if preferences.hotkey.usesHyper {
                    ShortcutRow(keys: Hotkey.clipboardHyper.description, action: "Clipboard history")
                    ShortcutRow(keys: "⇪ 1–9", action: "Switch profile")
                    ShortcutRow(keys: "⇪ Y or ⇪ N", action: "Allow or deny the request on screen")
                    ShortcutRow(keys: "⇪ 1–9", action: "Pick an answer while a question shows")
                } else {
                    ShortcutRow(keys: Hotkey.clipboardFallback.description, action: "Clipboard history")
                    ShortcutRow(keys: "⌃⌥⌘Y or ⌃⌥⌘N", action: "Allow or deny the request on screen")
                    ShortcutRow(keys: "⌃⌥⌘1–9", action: "Pick an answer while a question shows")
                }
                ShortcutRow(keys: "Esc", action: "Back to the grid, or close the shelf")
                ShortcutRow(keys: "Right-click the notch", action: "Menu: pages, tools, profiles, form, Settings")
            }

            Section("Dictation") {
                Toggle("Dictate by holding a key", isOn: $preferences.dictationEnabled)
                    .onChange(of: preferences.dictationEnabled) { _, on in
                        // Asked only now, when the feature is turned on.
                        if on { Task { await dictation.requestPermissions() } }
                    }
                if preferences.dictationEnabled {
                    Picker("Hold", selection: $preferences.dictationKey) {
                        ForEach(DictationKey.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Status") {
                        HStack {
                            Text(dictation.readiness.message).foregroundStyle(.secondary)
                            if dictation.readiness == .speechDenied {
                                Button("Open Settings") { Permission.speechRecognition.openSettings() }
                            } else if dictation.readiness == .microphoneDenied {
                                Button("Open Settings") { Permission.microphone.openSettings() }
                            } else if dictation.readiness == .needsPermission {
                                Button("Allow") { Task { await dictation.requestPermissions() } }
                            }
                        }
                    }
                }
                Text(
                    "Speak while you hold the key and let go to type it: into the prompt draft when a session is open in the Agents view, into a question card's answer, or else into the app in front. If the key also opens the shelf, a quick press still does. Speech is turned into text on this Mac; the audio never leaves it and nothing is kept."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .onAppear { dictation.refreshReadiness() }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            AdvancedSection {
                Toggle("Show Wisp in the menu bar", isOn: $preferences.showMenuBarIcon)
                if !preferences.showMenuBarIcon {
                    Text("Open Wisp again from Finder or Spotlight to get back to Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if preferences.hotkey.usesHyper {
                    Toggle(
                        "Pressing Caps Lock on its own still turns Caps Lock on",
                        isOn: $preferences.quickPressTogglesCapsLock)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var usesCapsLock: Binding<Bool> {
        Binding(
            get: { preferences.hotkey.usesHyper },
            set: { useCaps in
                preferences.hotkey =
                    useCaps ? .hyperSpace : Hotkey(keyCode: KeyCodes.space, modifiers: [.command, .shift])
            }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
            if LaunchAtLogin.needsApproval { LaunchAtLogin.openSystemSettings() }
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
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
