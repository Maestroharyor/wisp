import AppKit
import SwiftUI
import WispCore

struct WidgetSettings: View {
    @Bindable var preferences: Preferences
    let shortcuts: ShortcutsRunner

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
                Text("Five or fewer widgets always sit in one row with larger icons.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                if shortcuts.available.isEmpty {
                    Text("No Shortcuts found. Make some in the Shortcuts app.").foregroundStyle(.secondary)
                } else {
                    ForEach(shortcuts.available, id: \.self) { name in
                        Toggle(name, isOn: favourite(name))
                    }
                    Picker("Do Not Disturb toggle runs", selection: $preferences.doNotDisturbShortcut) {
                        Text("Nothing").tag("")
                        ForEach(shortcuts.available, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text(
                    "Ticked Shortcuts appear in the Shortcuts widget. macOS has no public Focus switch, so the Quick Toggles Focus button runs the Shortcut you choose (for example one using Set Focus)."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Timer") {
                DurationField(title: "New timers start at", seconds: $preferences.defaultTimerSeconds)
                Text("Type a length such as 10, 1h30m or 90s.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Day Progress") {
                Stepper(
                    "Day starts at \(preferences.workdayStart):00", value: $preferences.workdayStart,
                    in: 0...(preferences.workdayEnd - 1))
                Stepper(
                    "Day ends at \(preferences.workdayEnd):00", value: $preferences.workdayEnd,
                    in: (preferences.workdayStart + 1)...24)
            }
            Section("World Clocks") {
                ForEach(0..<3, id: \.self) { index in
                    Picker("City \(index + 1)", selection: zone(at: index)) {
                        Text("None").tag("")
                        ForEach(Self.zones, id: \.self) { Text(WorldClock.cityName($0) + "  (\($0))").tag($0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { shortcuts.refresh() }
    }

    private static let zones = TimeZone.knownTimeZoneIdentifiers.sorted {
        WorldClock.cityName($0) < WorldClock.cityName($1)
    }

    private func favourite(_ name: String) -> Binding<Bool> {
        Binding(
            get: { preferences.favouriteShortcuts.contains(name) },
            set: { on in
                if on {
                    preferences.favouriteShortcuts.append(name)
                } else {
                    preferences.favouriteShortcuts.removeAll { $0 == name }
                }
            })
    }

    private func zone(at index: Int) -> Binding<String> {
        Binding(
            get: { preferences.worldClockZones.indices.contains(index) ? preferences.worldClockZones[index] : "" },
            set: { identifier in
                var zones = preferences.worldClockZones
                while zones.count <= index { zones.append("") }
                zones[index] = identifier
                preferences.worldClockZones = zones.filter { !$0.isEmpty }
            })
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
