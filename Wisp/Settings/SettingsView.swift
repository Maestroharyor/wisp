import AppKit
import SwiftUI
import WispCore

/// Opens Settings in a normal window. Wisp is a menu bar app, so SwiftUI's Settings
/// scene does not come forward reliably; this does.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let services: AppServices
    private let hotkeys: HotkeyCenter

    init(services: AppServices, hotkeys: HotkeyCenter) {
        self.services = services
        self.hotkeys = hotkeys
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(services: services, hotkeys: hotkeys))
        let window = NSWindow(contentViewController: host)
        window.title = "Wisp Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 560, height: 520))
        return window
    }
}

struct SettingsView: View {
    let services: AppServices
    let hotkeys: HotkeyCenter

    var body: some View {
        TabView {
            GeneralSettings(preferences: services.preferences, hotkeys: hotkeys)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotchSettings(preferences: services.preferences)
                .tabItem { Label("Notch", systemImage: "capsule.portrait.inset.filled") }
            ActivitySettings(preferences: services.preferences)
                .tabItem { Label("Live Activities", systemImage: "waveform") }
            WidgetSettings(preferences: services.preferences)
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
            ClipboardSettings(preferences: services.preferences, store: services.clipboard)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            NotificationSettings(preferences: services.preferences, monitor: services.notifications)
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            PermissionSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 620, height: 560)
    }
}

private struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let hotkeys: HotkeyCenter

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
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

private struct NotchSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Opening") {
                Picker("Open the shelf on", selection: $preferences.openTrigger) {
                    ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if preferences.openTrigger == .hover {
                    LabeledContent("Open after hovering for") {
                        HStack {
                            Slider(value: $preferences.hoverDelay, in: 0...0.6, step: 0.05).frame(width: 160)
                            Text("\(Int(preferences.hoverDelay * 1000)) ms")
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
            Section("Look") {
                Picker("Animation", selection: $preferences.animationSpeed) {
                    ForEach(AnimationSpeed.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Glass edge", selection: $preferences.glassEdge) {
                    ForEach(GlassEdge.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Dragging files") {
                Picker("Show the drop basket", selection: $preferences.basketTrigger) {
                    ForEach(BasketTrigger.allCases) { Text($0.title).tag($0) }
                }
                Text("The basket appears next to the pointer with Drop, Transform, Zip and AirDrop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Displays without a notch") {
                Toggle("Show on external displays", isOn: $preferences.showOnExternalDisplays)
                Picker("Style", selection: $preferences.externalStyle) {
                    ForEach(ExternalStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!preferences.showOnExternalDisplays)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ActivitySettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Replace system overlays") {
                Toggle("Volume", isOn: $preferences.volumeHUD)
                Toggle("Display brightness", isOn: $preferences.brightnessHUD)
                Toggle("Caps Lock", isOn: $preferences.capsLockHUD)
                Text("Volume and brightness need Accessibility access to intercept the keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Show beside the notch") {
                Toggle("Now Playing (any app, including browsers)", isOn: $preferences.mediaActivity)
                Toggle("Battery and charging", isOn: $preferences.batteryHUD)
                Picker("Show on", selection: $preferences.activityDisplay) {
                    Text("Display under the pointer").tag(ActivityDisplayTarget.pointer)
                    Text("MacBook display").tag(ActivityDisplayTarget.builtIn)
                    Text("All displays").tag(ActivityDisplayTarget.all)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct WidgetSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Widgets") {
                ForEach(WidgetKind.allCases) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
                Text(
                    "Switched-on widgets appear as icons on the Widgets page: click one to open it, drag one to reorder. Up to four also sit on Home: right-click the notch and choose Customise Home to add, resize or reorder them."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Widgets page") {
                Picker("Rows", selection: $preferences.widgetGridRows) {
                    Text("One").tag(1)
                    Text("Two").tag(2)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for kind: WidgetKind) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledWidgets.contains(kind) },
            set: { enabled in
                if enabled { preferences.enable(kind) } else { preferences.disable(kind) }
            }
        )
    }
}

private struct ClipboardSettings: View {
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

private struct NotificationSettings: View {
    @Bindable var preferences: Preferences
    let monitor: NotificationMonitor

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show notifications in the notch", isOn: $preferences.notificationsEnabled)
                LabeledContent("Full Disk Access") {
                    HStack {
                        StatusDot(granted: monitor.hasAccess)
                        if !monitor.hasAccess {
                            Button("Open Settings") { Permission.fullDiskAccess.openSettings() }
                        }
                    }
                }
                Toggle("Hide the macOS banner", isOn: $preferences.hideSystemBanners)
                Toggle("Show Focus changes", isOn: $preferences.focusActivity)
                Text(
                    "macOS has no public way to read other apps' notifications, so Wisp reads the system's notification store. It needs Full Disk Access and could break after a macOS update."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Replies") {
                LabeledContent("iMessage and SMS", value: "Always on")
                Toggle("WhatsApp (via WhatsApp Web)", isOn: $preferences.whatsAppReplies)
                if preferences.whatsAppReplies {
                    Button("Log in to WhatsApp Web…") { monitor.showLogin(for: .whatsApp) }
                }
                Toggle("Telegram (via Telegram Web)", isOn: $preferences.telegramReplies)
                if preferences.telegramReplies {
                    Button("Log in to Telegram Web…") { monitor.showLogin(for: .telegram) }
                }
                Text("WhatsApp and Telegram replies drive their web apps and can stop working when those sites change.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !monitor.seenApps.isEmpty {
                Section("Apps") {
                    ForEach(monitor.seenApps.sorted { $0.value < $1.value }, id: \.key) { bundleID, name in
                        Toggle(name, isOn: allowed(bundleID))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func allowed(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { !preferences.blockedNotificationApps.contains(bundleID) },
            set: { allow in
                if allow {
                    preferences.blockedNotificationApps.removeAll { $0 == bundleID }
                } else if !preferences.blockedNotificationApps.contains(bundleID) {
                    preferences.blockedNotificationApps.append(bundleID)
                }
            }
        )
    }
}

private struct PermissionSettings: View {
    @State private var refresh = 0

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title)
                            Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let granted = permission.isGranted {
                            StatusDot(granted: granted)
                            if !granted { Button("Allow") { permission.request() } }
                        } else {
                            Button("Open Settings") { permission.openSettings() }
                        }
                    }
                    .id("\(permission.rawValue)-\(refresh)")
                }
            } footer: {
                Button("Refresh") { refresh += 1 }
            }
        }
        .formStyle(.grouped)
    }
}

private struct StatusDot: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(granted ? .green : .orange).frame(width: 8, height: 8)
            Text(granted ? "Granted" : "Not granted").foregroundStyle(.secondary)
        }
    }
}
