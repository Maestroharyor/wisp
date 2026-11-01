import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Theme, shape, motion and the playful extras, with presets that set them all at once.
struct AppearanceSettings: View {
    @Bindable var preferences: Preferences
    let services: AppServices

    @State private var naming = false
    @State private var newName = ""
    @State private var importError: String?
    @State private var exportError: String?

    private var look: Binding<Appearance> { $preferences.appearance }

    var body: some View {
        // The preview stays pinned above the list, so every change below shows in it.
        VStack(spacing: 0) {
            NotchPreview(preferences: preferences, accent: services.accent, glow: services.glow)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            Divider()
            form
        }
    }

    private var form: some View {
        Form {
            presets
            theme
            shell
            finish
            pills
            motion
            idle
            fun
            Section {
                Button("Reset the look to default", role: .destructive) { preferences.applyLook(.standard) }
            }
        }
        .formStyle(.grouped)
        .alert("Save this look", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { preferences.saveLook(named: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't import that look",
            isPresented: Binding(get: { importError != nil }, set: { _ in importError = nil })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert(
            "Couldn't export that look",
            isPresented: Binding(get: { exportError != nil }, set: { _ in exportError = nil })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: Presets

    private var presets: some View {
        Section("Presets") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(preferences.allLookPresets) { preset in
                    PresetChip(preset: preset, selected: preferences.isCurrentLook(preset.appearance)) {
                        preferences.applyLook(preset.appearance)
                    }
                    .contextMenu {
                        Button("Export…") { export(preset.appearance, name: preset.name) }
                        if !AppearancePreset.isBuiltIn(preset.name) {
                            Button("Delete", role: .destructive) { preferences.deleteLook(named: preset.name) }
                        }
                    }
                }
            }
            HStack {
                Button("Save current look…") {
                    newName = ""
                    naming = true
                }
                Button("Import…", action: importLook)
                Button("Export…") { export(preferences.appearance, name: "My look") }
            }
            if !preferences.profiles.isEmpty {
                ForEach(preferences.profiles) { profile in
                    Picker("Look for \(profile.name)", selection: profileLook(profile.name)) {
                        Text("Keep the current look").tag(String?.none)
                        ForEach(preferences.allLookPresets) { Text($0.name).tag(String?.some($0.name)) }
                    }
                }
            }
            caption(
                "A preset sets everything below at once. Right-click one to export it or delete it. A profile with a look applies it when it switches; one without a look brings yours back."
            )
        }
    }

    // MARK: Theme

    private var theme: some View {
        Section("Theme") {
            ThemePicker(preferences: preferences)
            if preferences.theme == .custom {
                ColorPicker("Accent", selection: $preferences.customAccent.color, supportsOpacity: false)
                ColorPicker("Glow", selection: $preferences.customGlow.color, supportsOpacity: false)
            }
            Toggle("Match the desktop picture", isOn: $preferences.wallpaperTint)
            Toggle("Tint with the playing album's colour", isOn: $preferences.adaptiveAccent)
            Picker("Through the day", selection: look.timeOfDay) {
                ForEach(TimeOfDayMode.allCases) { Text($0.title).tag($0) }
            }
            caption("The accent marks selection and progress. The glow runs from the accent to the glow colour.")
        }
    }

    // MARK: Shell

    private var shell: some View {
        Section("Shell") {
            Picker("Surface", selection: $preferences.surfaceStyle) {
                ForEach(SurfaceStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if preferences.surfaceStyle == .black {
                Picker("Glass edge", selection: look.glassEdge) {
                    ForEach(GlassEdge.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            slider("Roundness", value: look.roundness, in: Appearance.roundnessRange)
            Picker("Shadow", selection: look.shadow) {
                ForEach(ShellShadow.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if preferences.surfaceStyle != .glass {
                slider("Opacity", value: look.opacity, in: Appearance.opacityRange)
            }
            Picker("Shelf size", selection: look.shelfSize) {
                ForEach(ShelfSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            caption("The closed notch keeps its shape and stays black, so it still matches the camera.")
        }
    }

    // MARK: Finish

    private var finish: some View {
        Section("Finish") {
            slider("Glow strength", value: look.glowIntensity, in: Appearance.glowRange)
            if preferences.surfaceStyle == .tinted {
                slider("Glow reach", value: look.glowSpread, in: Appearance.glowRange)
            }
            Picker("Grain", selection: look.grain) {
                ForEach(GrainLevel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if preferences.surfaceStyle == .tinted {
                Toggle("Shimmer (the glow drifts slowly)", isOn: look.shimmer)
            }
            Picker("Outline", selection: look.outline) {
                ForEach(OutlineWidth.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Page switcher", selection: look.navPill) {
                ForEach(NavPillStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            caption(
                preferences.appearance.navPill == .hidden
                    ? "Switch pages from the Open menu when you right-click the notch."
                    : "Glow strength sets the Tinted glow and the rim glows. Reach and shimmer apply to the Tinted surface."
            )
        }
    }

    // MARK: Pills

    private var pills: some View {
        Section("Live activity pills") {
            Toggle("Minimal pill (an icon and a dot, no labels)", isOn: look.minimalPill)
            Picker("Numbers in", selection: look.valueFont) {
                ForEach(ValueFont.allCases) { font in
                    Text(font.title).font(.system(.body, design: font.design)).tag(font)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Motion

    private var motion: some View {
        Section("Motion") {
            Picker("Animation", selection: look.animationSpeed) {
                ForEach(AnimationSpeed.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("When the pointer arrives", selection: look.hoverFeedback) {
                ForEach(HoverFeedback.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if preferences.appearance.hoverFeedback != .none {
                slider("Strength", value: look.hoverStrength, in: Appearance.hoverStrengthRange)
            }
            caption("Reduce Motion in System Settings turns off the wobble, the shimmer and confetti.")
        }
    }

    // MARK: Idle

    private var idle: some View {
        Section("While idle") {
            Picker("Left of the notch", selection: look.leftEar) {
                ForEach(EarSlot.allCases) { Text($0.title).tag($0) }
            }
            Picker("Right of the notch", selection: look.rightEar) {
                ForEach(EarSlot.allCases) { Text($0.title).tag($0) }
            }
            if [preferences.appearance.leftEar, preferences.appearance.rightEar].contains(.custom) {
                TextField("My text", text: look.earText, prompt: Text("Up to 12 characters, emoji too"))
                    .onChange(of: preferences.appearance.earText) { _, text in
                        if text.count > Appearance.earTextLimit {
                            preferences.appearance.earText = String(text.prefix(Appearance.earTextLimit))
                        }
                    }
            }
            Toggle("Breathing glow while an agent works, music plays or a timer runs", isOn: look.breathingGlow)
            Toggle("Glow pulses to the music", isOn: look.musicGlow)
            caption(
                "Ears show beside the closed notch when nothing else is there; not on the left or right edge. The music pulse keeps a steady beat; Wisp doesn't listen to the audio."
            )
        }
    }

    // MARK: Fun

    private var fun: some View {
        Section("Fun") {
            Picker("Sounds", selection: look.soundPack) {
                ForEach(SoundPackID.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if preferences.appearance.soundPack != .off {
                ForEach(SoundEvent.allCases) { event in
                    soundRow(event)
                }
            }
            Toggle("Confetti when a Pomodoro focus ends", isOn: look.confettiPomodoro)
            Toggle("Confetti when an agent finishes a long run", isOn: look.confettiAgent)
            Toggle("Confetti when the battery is full", isOn: look.confettiBattery)
            Toggle("Notch pet", isOn: look.pet)
            HStack {
                Button("Try confetti") { services.celebrateNow() }
                Spacer()
            }
            caption(
                "The pet is a small flame that peeks out from under the notch. It dozes off when nothing happens and wakes when an agent needs you."
            )
        }
    }

    private func soundRow(_ event: SoundEvent) -> some View {
        let custom = preferences.appearance.soundPack == .custom
        let path = preferences.appearance.customSounds[event.rawValue]
        return LabeledContent(event.title) {
            HStack {
                if custom {
                    Text(path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Choose…") { chooseSound(for: event) }
                }
                Button {
                    services.sounds.play(event)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play")
            }
        }
    }

    // MARK: Helpers

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range).frame(width: 180)
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func profileLook(_ name: String) -> Binding<String?> {
        Binding(
            get: { preferences.profile(named: name)?.look },
            set: { preferences.setLook($0, forProfile: name) })
    }

    private static var lookType: UTType { UTType(filenameExtension: LookFile.fileExtension) ?? .json }

    private func export(_ appearance: Appearance, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.lookType]
        panel.nameFieldStringValue = "\(name).\(LookFile.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let title = url.deletingPathExtension().lastPathComponent
        do {
            try LookFile(name: title, appearance: appearance).encoded().write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func importLook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.lookType, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try LookFile.decode(try Data(contentsOf: url))
            let name = preferences.addLook(file)
            if let preset = preferences.lookPreset(named: name) { preferences.applyLook(preset.appearance) }
        } catch LookFile.ReadError.newerVersion {
            importError = "It was made by a newer version of Wisp."
        } catch {
            importError = "The file isn't a Wisp look."
        }
    }

    private func chooseSound(for event: SoundEvent) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.appearance.customSounds[event.rawValue] = url.path
    }
}

/// A preset as a small swatch of its accent and glow over its surface.
private struct PresetChip: View {
    let preset: AppearancePreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let palette = ThemeCatalog.palette(
            for: preset.appearance.theme,
            custom: ThemePalette(accent: preset.appearance.customAccent, glow: preset.appearance.customGlow))
        let accent = Color(rgb: palette.accent)
        let look = preset.appearance
        let shape = RoundedRectangle(cornerRadius: 10 * look.roundness, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                // The preset's real surface, with an accent bar so Black presets differ too.
                SurfaceBackground(
                    style: look.surface, glass: look.glassEdge, accent: accent, glow: Color(rgb: palette.glow),
                    intensity: look.glowIntensity, spread: look.glowSpread * 0.3
                )
                .overlay(alignment: .bottomLeading) {
                    Capsule().fill(accent).frame(width: 34, height: 3).padding(8)
                }
                .clipShape(shape)
                .frame(height: 40)
                .overlay(shape.strokeBorder(selected ? accent : .white.opacity(0.12), lineWidth: 2))
                Text(preset.name).font(.caption).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
