import SwiftUI
import WispCore

/// Every keyboard shortcut in one place: Caps Lock as Hyper, a recorder for each one Wisp lets
/// you change, and the keys that stay fixed.
struct ShortcutsSettings: View {
    @Bindable var preferences: Preferences
    let hotkeys: HotkeyCenter

    var body: some View {
        Form {
            Section {
                Toggle("Use Caps Lock as Hyper", isOn: usesCapsLock)
                LabeledContent("Status") {
                    HStack {
                        Text(hotkeys.status.message).foregroundStyle(.secondary)
                        if hotkeys.status == .needsAccessibility {
                            Button("Open Accessibility Settings", action: AccessibilityPermission.openSettings)
                        }
                    }
                }
            } header: {
                SettingsHeader("Caps Lock")
            } footer: {
                Text(
                    "Held, Caps Lock becomes Hyper (⇪), a modifier no other app uses, so ⇪ shortcuts never clash. A quick press can still turn Caps Lock on (General › Advanced); needs Accessibility."
                )
            }

            Section {
                LabeledContent("Open or close the shelf") {
                    if preferences.hotkey.usesHyper {
                        KeyCap(Hotkey.hyperSpace.description)
                    } else {
                        HotkeyRecorder(hotkey: $preferences.hotkey, hotkeys: hotkeys) { candidate in
                            shelfClash(candidate)
                        }
                    }
                }
                ForEach(ShortcutAction.allCases) { action in
                    row(action)
                }
                Button("Reset all shortcuts") {
                    preferences.shortcuts = ShortcutMap()
                }
                .disabled(preferences.shortcuts == ShortcutMap())
            } header: {
                SettingsHeader("Shortcuts")
            } footer: {
                Text(
                    "Click a shortcut and press the new keys; Esc cancels. Keys already in use are refused with what uses them, and ⇪ shortcuts need Caps Lock as Hyper."
                )
            }

            Section(header: "Fixed keys") {
                let approve = preferences.hotkey.usesHyper ? "⇪ Y or ⇪ N" : "⌃⌥⌘Y or ⌃⌥⌘N"
                let digits = preferences.hotkey.usesHyper ? "⇪ 1–9" : "⌃⌥⌘1–9"
                FixedShortcut(keys: approve, action: "Allow or deny the request on screen")
                FixedShortcut(keys: digits, action: "Pick an answer while a question shows")
                if preferences.hotkey.usesHyper {
                    FixedShortcut(keys: "⇪ 1–9", action: "Switch profile")
                }
                FixedShortcut(keys: "Esc", action: "Back to the grid, or close the shelf")
                FixedShortcut(keys: "Right-click the notch", action: "Menu: pages, tools, profiles, form, Settings")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func row(_ action: ShortcutAction) -> some View {
        let shelf = preferences.hotkey
        let current = preferences.shortcuts.key(for: action, shelf: shelf)
        LabeledContent(action.title) {
            HStack(spacing: 8) {
                if let current {
                    HotkeyRecorder(hotkey: binding(for: action, current: current), hotkeys: hotkeys) { candidate in
                        preferences.shortcuts.clash(
                            candidate, for: action, shelf: shelf, holdKey: holdKey)
                    }
                } else {
                    Text("Off").foregroundStyle(.secondary)
                }
                Menu {
                    Button(current == nil ? "Turn on" : "Turn off") {
                        if current == nil {
                            preferences.shortcuts.reset(action)
                        } else {
                            preferences.shortcuts.set(nil, for: action)
                        }
                    }
                    Button("Use the default") { preferences.shortcuts.reset(action) }
                        .disabled(!preferences.shortcuts.isCustom(action))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Options for \(action.title)")
            }
        }
        if hotkeys.unavailable.contains(action), let current {
            Text(
                current.usesHyper && !shelf.usesHyper
                    ? "\(current.description) needs Caps Lock as Hyper. Turn it on above, or choose another shortcut."
                    : "Another app uses \(current.description). Choose another shortcut."
            )
            .wispFont(.caption).foregroundStyle(.orange)
        }
    }

    private func binding(for action: ShortcutAction, current: Hotkey) -> Binding<Hotkey> {
        Binding(get: { current }, set: { preferences.shortcuts.set($0, for: action) })
    }

    /// Dictation's key, held with Caps Lock, when dictation is on.
    private var holdKey: UInt16? {
        preferences.dictationEnabled ? preferences.dictationKey.keyCode : nil
    }

    /// The shelf's own shortcut can't take another action's key.
    private func shelfClash(_ candidate: Hotkey) -> String? {
        ShortcutAction.allCases.first { preferences.shortcuts.key(for: $0, shelf: candidate) == candidate }?.title
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
}

/// A shortcut that can't be changed, shown as key caps.
private struct FixedShortcut: View {
    let keys: String
    let action: String

    var body: some View {
        LabeledContent(action) { KeyCap(keys) }
    }
}

/// Keys drawn as a small cap.
struct KeyCap: View {
    let keys: String

    init(_ keys: String) {
        self.keys = keys
    }

    var body: some View {
        Text(keys)
            .wispFont(.callout, weight: .medium)
            .fontDesign(.rounded)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: SurfaceRadius.control - 3, style: .continuous).fill(.quaternary))
    }
}
