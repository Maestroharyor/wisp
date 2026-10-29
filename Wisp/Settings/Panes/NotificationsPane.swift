import AppKit
import SwiftUI
import WispCore

struct NotificationSettings: View {
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
