import AppKit
import SwiftUI
import WispCore

struct NotchSettings: View {
    @Bindable var preferences: Preferences
    let accent: Color

    var body: some View {
        Form {
            Section {
                NotchPreview(preferences: preferences, accent: accent)
            }
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
                Picker("Once open", selection: $preferences.shelfAutoCloses) {
                    Text("Close when the pointer leaves").tag(true)
                    Text("Stay open").tag(false)
                }
                if !preferences.shelfAutoCloses {
                    Text("Close it by clicking outside the shelf, pressing Esc or the shortcut.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Look") {
                Picker("Animation", selection: $preferences.animationSpeed) {
                    ForEach(AnimationSpeed.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Surface", selection: $preferences.surfaceStyle) {
                    ForEach(SurfaceStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if preferences.surfaceStyle == .black {
                    Picker("Glass edge", selection: $preferences.glassEdge) {
                        ForEach(GlassEdge.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if preferences.surfaceStyle != .black {
                    Toggle("Tint with the playing album's colour", isOn: $preferences.adaptiveAccent)
                }
                Text(
                    "Glass uses Liquid Glass and shows the wallpaper through the open shelf. Tinted keeps black with a soft colour glow. The closed notch always stays black."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dragging files") {
                Picker("Show the drop pocket", selection: $preferences.pocketTrigger) {
                    ForEach(PocketTrigger.allCases) { Text($0.title).tag($0) }
                }
                Text("The pocket appears next to the pointer with Drop, Transform, Zip and AirDrop.")
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
