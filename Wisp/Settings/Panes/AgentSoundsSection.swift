import AppKit
import SwiftUI
import WispCore

/// Settings › Agents › Sounds: a row per agent moment with its switch, sound and a preview,
/// then muting during calls or Focus. The volume is under Advanced (`AgentSoundVolume`).
struct AgentSoundsSection: View {
    @Bindable var preferences: Preferences
    let player: SoundPlayer

    var body: some View {
        Section {
            ForEach(AgentSoundEvent.allCases) { event in
                AgentSoundRow(event: event, preferences: preferences, player: player)
            }
            Toggle("Mute during calls or Focus", isOn: $preferences.agentSounds.muteDuringCallsOrFocus)
        } header: {
            Text("Sounds")
        } footer: {
            Text(
                "A burst of requests from one session chimes once. Failed is an agent that quit without ending its session. A call is the microphone in use by a call app; Focus is read only with Full Disk Access, as notifications need. The sound pack in Appearance doesn't change these."
            )
        }
    }
}

/// One moment: on or off, which sound, and a play button.
private struct AgentSoundRow: View {
    let event: AgentSoundEvent
    @Bindable var preferences: Preferences
    let player: SoundPlayer

    private var setting: Binding<AgentSoundSetting> {
        Binding(get: { preferences.agentSounds[event] }, set: { preferences.agentSounds[event] = $0 })
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(event.title, isOn: setting.on)
            Spacer(minLength: 8)
            Menu {
                ForEach(SoundPlayer.systemSounds, id: \.self) { name in
                    Button(name) { setting.wrappedValue.sound = .system(name) }
                }
                Divider()
                if case .file(let path) = setting.wrappedValue.sound {
                    Button(Self.name(of: .file(path))) {}.disabled(true)
                }
                Button("Choose file…") { chooseFile() }
            } label: {
                Text(Self.name(of: setting.wrappedValue.sound)).lineLimit(1)
            }
            .fixedSize()
            .disabled(!setting.wrappedValue.on)
            Button {
                player.play(setting.wrappedValue.sound, volume: preferences.agentSounds.volume)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(event.title)")
        }
    }

    /// A system sound's name, or a picked file's name without its extension.
    private static func name(of sound: SoundSource) -> String {
        switch sound {
        case .system(let name): name
        case .file(let path): URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }

    /// Wisp reads only the file picked here; its path is kept, as for the sound pack's files.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setting.wrappedValue.sound = .file(url.path)
    }
}

/// The agent sounds' volume, for the Advanced disclosure.
struct AgentSoundVolume: View {
    @Bindable var preferences: Preferences

    var body: some View {
        LabeledContent("Agent sound volume") {
            Slider(value: $preferences.agentSounds.volume, in: 0...1)
                .frame(width: 160)
        }
    }
}
