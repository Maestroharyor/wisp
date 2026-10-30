import AppKit
import SwiftUI
import WispCore

struct ActivitySettings: View {
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
                Toggle("Lyrics from LRCLIB (sends the song title, artist and length)", isOn: $preferences.lyrics)
                Toggle("Player on the lock screen, where macOS allows it", isOn: $preferences.lockScreenPlayer)
                Toggle(
                    "Meetings: a pill while the microphone is on, and a Join card before calls",
                    isOn: $preferences.meetingActivity)
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
