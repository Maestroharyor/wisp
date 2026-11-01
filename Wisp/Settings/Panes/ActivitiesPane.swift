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
                Picker("Stay on screen", selection: $preferences.hudDuration) {
                    ForEach(HUDDuration.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Volume steps", selection: $preferences.volumeSteps) {
                    ForEach([8, 16, 32, 64], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Use the theme accent for the level bars", isOn: $preferences.hudUsesAccent)
                Text(
                    "Volume and brightness need Accessibility access to intercept the keys. Hold Option and Shift for steps four times finer."
                )
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
                    "Meetings: a pill while the microphone is on, and a Join card before calls",
                    isOn: $preferences.meetingActivity)
                Toggle("Battery and charging", isOn: $preferences.batteryHUD)
                Picker("Warn when the battery reaches", selection: $preferences.batteryLowThreshold) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(!preferences.batteryHUD)
                Toggle("Headphones connecting, with their battery", isOn: $preferences.deviceActivity)
                Toggle("Split extra activities into bubbles beside the notch", isOn: $preferences.activityBubbles)
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
}
