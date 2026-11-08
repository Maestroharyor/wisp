import AppKit
import SwiftUI
import WispCore

struct ActivitySettings: View {
    @Bindable var preferences: Preferences
    let downloads: DownloadMonitor
    let notifications: NotificationMonitor

    var body: some View {
        Form {
            Section("Use Wisp for these pop-ups") {
                Toggle("Volume", isOn: $preferences.volumeHUD)
                Toggle("Display brightness", isOn: $preferences.brightnessHUD)
                Toggle("Caps Lock", isOn: $preferences.capsLockHUD)
                Text("Volume and brightness need Accessibility access to intercept the keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Show beside the notch") {
                Toggle("Now Playing (any app, including browsers)", isOn: $preferences.mediaActivity)
                Toggle("Lyrics from LRCLIB (sends the song title, artist, album and length)", isOn: $preferences.lyrics)
                Toggle(
                    "Find missing album art on iTunes (sends the song title and artist)",
                    isOn: $preferences.artworkLookup)
                Toggle("Player on the lock screen, where macOS allows it", isOn: $preferences.lockScreenPlayer)
                Toggle(
                    "Calls and recordings: a pill while the microphone is on, and a Join card before calls",
                    isOn: $preferences.meetingActivity)
                Toggle(
                    "Call controls: click the call pill to mute, turn the camera on or off, share or leave in Zoom",
                    isOn: $preferences.meetingControls
                )
                .disabled(!preferences.meetingActivity)
                Toggle("Focus changes", isOn: $preferences.focusActivity)
                if preferences.focusActivity && !notifications.hasAccess {
                    LabeledContent("Focus needs Full Disk Access") {
                        Button("Allow") { Permission.fullDiskAccess.request() }
                    }
                }
                Toggle("Show more than one activity at once", isOn: $preferences.activityBubbles)
                Text("Extra activities get their own bubbles beside the notch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Batteries") {
                Toggle("Battery and charging", isOn: $preferences.batteryHUD)
                Toggle("Mouse, keyboard and trackpad batteries", isOn: $preferences.accessoryBatteries)
                Picker("Warn when a battery reaches", selection: $preferences.batteryLowThreshold) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(!preferences.batteryHUD && !preferences.accessoryBatteries)
                Toggle("Headphones connecting, with their battery", isOn: $preferences.deviceActivity)
            }
            Section("Downloads") {
                Toggle("Download progress, with Open when it's done", isOn: $preferences.downloadActivity)
                LabeledContent("Downloads") {
                    Text("Always watched").foregroundStyle(.secondary)
                }
                .disabled(!preferences.downloadActivity)
                ForEach(preferences.downloadFolders, id: \.self) { path in
                    LabeledContent((path as NSString).abbreviatingWithTildeInPath) {
                        Button("Remove") { preferences.downloadFolders.removeAll { $0 == path } }
                    }
                }
                .disabled(!preferences.downloadActivity)
                Button("Add folder…", action: addDownloadFolder)
                    .disabled(!preferences.downloadActivity)
                Text(
                    "Works with Safari, Chrome, Edge, Brave, Arc and Firefox. Wisp reads only file names and sizes, and macOS may ask before it can see the Downloads folder."
                )
                .font(.caption).foregroundStyle(.secondary)
                if !downloads.deniedFolders.isEmpty {
                    Text(
                        "Wisp can't see \(downloads.deniedFolders.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")). Allow it in System Settings › Privacy & Security › Files and Folders."
                    )
                    .font(.caption).foregroundStyle(.orange)
                }
            }
            AdvancedSection {
                Picker("Pop-ups stay on screen", selection: $preferences.hudDuration) {
                    ForEach(HUDDuration.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Use the theme accent for the level bars", isOn: $preferences.hudUsesAccent)
                Picker("Volume steps", selection: $preferences.volumeSteps) {
                    ForEach([8, 16, 32, 64], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Hold Option and Shift while changing the volume for steps four times finer.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(
                    "Call controls for Teams and Google Meet in Chromium browsers",
                    isOn: $preferences.meetingShortcutControls
                )
                .disabled(!preferences.meetingActivity || !preferences.meetingControls)
                Text(
                    "Wisp types their keyboard shortcuts into the call window. Teams and Meet don't say whether you're muted, so their buttons only toggle. Wisp can't always tell Teams' call window from its other windows, so this is off until you turn it on."
                )
                .font(.caption).foregroundStyle(.secondary)
                Picker("First bubble", selection: $preferences.firstBubbleOnLeft) {
                    Text("Right").tag(false)
                    Text("Left").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!preferences.activityBubbles)
                Picker("Show on", selection: $preferences.activityDisplay) {
                    Text("Display under the pointer").tag(ActivityDisplayTarget.pointer)
                    Text("MacBook display").tag(ActivityDisplayTarget.builtIn)
                    Text("All displays").tag(ActivityDisplayTarget.all)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.map(\.path).filter { !preferences.downloadFolders.contains($0) }
        preferences.downloadFolders += chosen
    }
}
