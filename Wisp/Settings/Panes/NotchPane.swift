import AppKit
import SwiftUI
import WispCore

struct NotchSettings: View {
    @Bindable var preferences: Preferences
    let accent: Color
    let glow: Color
    let shortcuts: ShortcutsRunner

    /// Re-read when displays are plugged in or removed while Settings is open.
    @State private var screens = NSScreen.screens

    var body: some View {
        Form {
            Section {
                NotchPreview(preferences: preferences, accent: accent, glow: glow)
            }
            Section("Position") {
                Picker("Sit at", selection: $preferences.placement) {
                    ForEach(Placement.allCases) { Text($0.title).tag($0) }
                }
                Text(
                    "Top uses the notch. The left and right edges get a notch on its side. The corners and the bottom float an island below the menu bar or above the Dock. The floating orb goes anywhere: drag it, or pull the notch down to tear it off, and drop it at the top centre to dock it. Drag an island to move it; it stays where you drop it on that display. The shelf grows out from wherever it sits."
                )
                .font(.caption).foregroundStyle(.secondary)
                if hasSystemIsland {
                    Text("Apple's Dynamic Island sits at the top of this Mac, so Top moves to the top right.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Dynamic Island") {
                Picker("This Mac has a Dynamic Island", selection: $preferences.islandSetting) {
                    Text("Automatic").tag(IslandSetting.automatic)
                    Text("Yes").tag(IslandSetting.yes)
                    Text("No").tag(IslandSetting.no)
                }
                Text(
                    "On a MacBook Pro with a Dynamic Island, Wisp stays clear of it. Choose Yes if Wisp draws over the island."
                )
                .font(.caption).foregroundStyle(.secondary)
                Button("Copy display info") { copyDisplayInfo() }
                    .help("Copies the model and screen measurements Wisp uses to find the notch or island")
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
                Picker("Once open", selection: $preferences.shelfClosing) {
                    Text("Close when the pointer leaves").tag(ShelfClosing.pointerLeaves)
                    Text("Close when I click elsewhere").tag(ShelfClosing.clickElsewhere)
                    Text("Stay open until I close it").tag(ShelfClosing.never)
                }
                if preferences.shelfClosing == .never {
                    Text(
                        "Close it with Esc or the shortcut. A shelf opened by dragging a file still closes when the drag leaves."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Trackpad swipes on the notch", isOn: $preferences.swipeGestures)
                Text(
                    "Two fingers away from the edge on the closed notch opens the shelf. Along the edge on the music pill skips tracks."
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
            Section("Drop actions") {
                DropActionsEditor(preferences: preferences, shortcuts: shortcuts)
            }
            Section("Displays without a notch") {
                Toggle("Show on external displays", isOn: $preferences.showOnExternalDisplays)
                Picker("Style", selection: $preferences.externalStyle) {
                    ForEach(ExternalStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!preferences.showOnExternalDisplays)
            }
            Section("Each display") {
                ForEach(screens, id: \.displayUUID) { screen in
                    if let uuid = screen.displayUUID {
                        Picker(
                            DisplayName.title(
                                name: screen.localizedName, builtIn: screen.isBuiltIn,
                                width: Int(screen.frame.width), height: Int(screen.frame.height)),
                            selection: displayStyle(uuid)
                        ) {
                            Text("Automatic").tag(DisplayStyle.automatic)
                            Text("Notch").tag(DisplayStyle.notch)
                            if !screen.metrics.hasCameraHousing {
                                Text("Floating island").tag(DisplayStyle.island)
                            }
                            Text("Hidden").tag(DisplayStyle.hidden)
                        }
                        Picker("Position", selection: placementOverride(uuid)) {
                            Text("Default (\(preferences.placement.title))").tag(Placement?.none)
                            ForEach(Placement.allCases) { Text($0.title).tag(Placement?.some($0)) }
                        }
                        .padding(.leading, 16)
                        if let layout = preferences.layout(for: screen, uuid: uuid), layout.moved {
                            LabeledContent("Moved by dragging") {
                                Button("Move back to the \(layout.placement.title.lowercased())") {
                                    preferences.moveIslandBack(uuid)
                                }
                            }
                            .padding(.leading, 16)
                        }
                    }
                }
                Text(
                    "Automatic follows the settings above. Notch and island apply at the top. Choices are remembered per display."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) {
            _ in
            screens = NSScreen.screens
        }
    }

    private var hasSystemIsland: Bool {
        screens.contains { $0.hasSystemIsland(preferences.islandSetting) }
    }

    private func copyDisplayInfo() {
        let text = screens.map(\.islandReport).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func placementOverride(_ uuid: String) -> Binding<Placement?> {
        Binding(
            get: { preferences.placementOverride(for: uuid) },
            set: { preferences.setPlacementOverride($0, for: uuid) })
    }

    private func displayStyle(_ uuid: String) -> Binding<DisplayStyle> {
        Binding(
            get: { preferences.displayStyle(for: uuid) },
            set: { preferences.setDisplayStyle($0, for: uuid) })
    }
}
