import AppKit
import SwiftUI
import WispCore

struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let hotkeys: HotkeyCenter
    let accent: Color
    let missing: [Permission]
    let fixPermissions: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                NotchPreview(preferences: preferences, accent: accent)
                if !missing.isEmpty {
                    HealthBanner(missing: missing, fix: fixPermissions)
                }
            }
            Section("Shortcut") {
                Toggle("Open the shelf with Caps Lock + Space", isOn: usesCapsLock)
                if preferences.hotkey.usesHyper {
                    Toggle(
                        "Pressing Caps Lock on its own still turns Caps Lock on",
                        isOn: $preferences.quickPressTogglesCapsLock)
                } else {
                    LabeledContent("Shortcut") {
                        HotkeyRecorder(hotkey: $preferences.hotkey)
                    }
                }
                LabeledContent("Clipboard history") {
                    Text(
                        preferences.hotkey.usesHyper
                            ? Hotkey.clipboardHyper.description : Hotkey.clipboardFallback.description
                    )
                    .foregroundStyle(.secondary)
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

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
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
