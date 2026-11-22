import AppKit
import SwiftUI
import WispCore

struct NotchSettings: View {
    @Bindable var preferences: Preferences
    let accent: Color
    let glow: Color
    let shortcuts: ShortcutsRunner
    let shelfWindow: ShelfWindowController

    /// Re-read when displays are plugged in or removed while Settings is open.
    @State private var screens = NSScreen.screens

    var body: some View {
        Form {
            Section {
                NotchPreview(preferences: preferences, accent: accent, glow: glow)
            }
            Section {
                Picker("Sit at", selection: $preferences.placement) {
                    ForEach(Placement.allCases) { Text($0.title).tag($0) }
                }
                if hasSystemIsland {
                    Text("Apple's Dynamic Island sits at the top of this Mac, so Top moves to the top right.")
                        .wispFont(.caption).foregroundStyle(.secondary)
                }
                Picker("On displays without a notch", selection: $preferences.notchlessDisplays) {
                    ForEach(NotchlessDisplayChoice.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Position")
            } footer: {
                Text(
                    "Top uses the notch, Bottom turns it upside down on the Dock, and Left and Right lay it on its side. Corner islands and the orb go where you drag them (pull the notch down to tear off the orb, drop it at the top centre to dock it), and the shelf grows out from wherever Wisp sits."
                )
            }
            Section {
                Toggle("Open the shelf in a window", isOn: windowForm)
            } header: {
                Text("Window")
            } footer: {
                Text(
                    "Wisp's pages open in a window you can move and resize; minimise or close it to go back to the notch, island or orb, and click that or press the shortcut to return. For a one-off window, choose Form › Open as Window from the right-click menu or pull the open shelf away by its edge."
                )
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
                    .wispFont(.caption).foregroundStyle(.secondary)
                }
                Toggle("Trackpad swipes on the notch", isOn: $preferences.swipeGestures)
                Text(
                    "Two fingers away from the edge on the closed notch opens the shelf. Along the edge on the music pill skips tracks."
                )
                .wispFont(.caption).foregroundStyle(.secondary)
                LabeledContent("Shelf height") {
                    Button("Reset all pages") { preferences.shelfHeights = [:] }
                        .disabled(preferences.shelfHeights.isEmpty)
                }
                Text(
                    "Drag the handle on the open shelf's bottom edge to make Agents, Clipboard, Calendar and other lists taller. Double-click it to reset one page. At the top of the screen only."
                )
                .wispFont(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Show the drop pocket", selection: $preferences.pocketTrigger) {
                    ForEach(PocketTrigger.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Dragging files")
            } footer: {
                Text("The pocket appears next to the pointer with Drop, Transform, Zip and AirDrop.")
            }
            Section("Drop actions") {
                DropActionsEditor(preferences: preferences, shortcuts: shortcuts)
            }
            AdvancedSection {
                Picker("Dynamic Island detection", selection: $preferences.islandSetting) {
                    ForEach(IslandSetting.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(
                    "On a MacBook Pro with a Dynamic Island, Wisp stays clear of it. Choose Has a Dynamic Island if Wisp draws over it, and paste About › Copy diagnostics into a bug report."
                )
                .wispFont(.caption).foregroundStyle(.secondary)
                Text("Displays").wispFont(.headline).padding(.top, 6)
                ForEach(screens, id: \.displayUUID) { screen in
                    if let uuid = screen.displayUUID {
                        displayRows(screen, uuid: uuid)
                    }
                }
                Text(
                    "Automatic follows the choice for displays without a notch. Notch and island apply at the top. Choices are remembered per display."
                )
                .wispFont(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) {
            _ in
            screens = NSScreen.screens
        }
    }

    @ViewBuilder private func displayRows(_ screen: NSScreen, uuid: String) -> some View {
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

    private var hasSystemIsland: Bool {
        screens.contains { $0.hasSystemIsland(preferences.islandSetting) }
    }

    /// Goes through the window's rules, so turning it on opens the window and off puts it away.
    private var windowForm: Binding<Bool> {
        Binding(get: { preferences.windowForm }, set: { shelfWindow.setWindowForm($0) })
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
