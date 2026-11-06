import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WispCore

struct RingSettings: View {
    @Bindable var preferences: Preferences
    let trigger: RingTrigger

    var body: some View {
        Form {
            Section("Opening") {
                if preferences.hotkey.usesHyper {
                    LabeledContent("Hyper key", value: "Hyper+R, at the pointer")
                }
                Toggle("Keyboard shortcut", isOn: hasRingHotkey)
                if preferences.ringHotkey != nil {
                    LabeledContent("Shortcut") { HotkeyRecorder(hotkey: ringHotkey) }
                }
                Picker("Mouse button", selection: $preferences.ringButton) {
                    ForEach(RingButton.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if preferences.ringButton != .off {
                    LabeledContent("Status", value: trigger.status.message)
                }
                Toggle("Clicking the orb opens the ring", isOn: $preferences.ringOnOrbClick)
                Text(
                    "Hold the mouse button, move to an action and let go, or click it quickly to leave the ring open. Other apps stop seeing the button you choose, and it needs Accessibility. The centre of the ring opens the shelf; files dragged onto the orb open the ring to drop them on an action."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ring") {
                RingSetEditor(set: standard, dropActions: preferences.dropActions)
                Button("Reset to the default ring") { preferences.ringConfig.standard = RingConfig.defaults.standard }
            }
            Section("Rings for apps") {
                ForEach(preferences.ringConfig.perApp) { set in
                    DisclosureGroup {
                        RingSetEditor(set: perApp(set.id), dropActions: preferences.dropActions)
                    } label: {
                        HStack {
                            Text(set.name)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                preferences.ringConfig.perApp.removeAll { $0.id == set.id }
                            }
                        }
                    }
                }
                Button("Add a ring for an app…") { addAppRing() }
                Text("When that app is in front, its ring opens instead of the one above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static let suggestedHotkey = Hotkey(keyCode: KeyCodes.r, modifiers: [.control, .option, .command])

    private var hasRingHotkey: Binding<Bool> {
        Binding(
            get: { preferences.ringHotkey != nil },
            set: { preferences.ringHotkey = $0 ? Self.suggestedHotkey : nil })
    }

    private var ringHotkey: Binding<Hotkey> {
        Binding(
            get: { preferences.ringHotkey ?? Self.suggestedHotkey }, set: { preferences.ringHotkey = $0 })
    }

    private var standard: Binding<RingSet> {
        Binding(get: { preferences.ringConfig.standard }, set: { preferences.ringConfig.standard = $0 })
    }

    private func perApp(_ id: UUID) -> Binding<RingSet> {
        Binding(
            get: { preferences.ringConfig.perApp.first { $0.id == id } ?? preferences.ringConfig.standard },
            set: { updated in
                guard let index = preferences.ringConfig.perApp.firstIndex(where: { $0.id == id }) else { return }
                preferences.ringConfig.perApp[index] = updated
            })
    }

    private func addAppRing() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
            let id = bundle.bundleIdentifier
        else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        preferences.ringConfig.perApp.append(
            RingSet(name: name, slots: preferences.ringConfig.standard.slots, bundleIDs: [id]))
    }
}

/// The segments of one ring, in order from 12 o'clock, each with an optional sub-ring.
private struct RingSetEditor: View {
    @Binding var set: RingSet
    let dropActions: [DropAction]

    var body: some View {
        ForEach(Array(set.slots.enumerated()), id: \.offset) { index, slot in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 16)
                    RingActionPicker(action: actionBinding(index), dropActions: dropActions)
                    Button {
                        move(index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .help("Move earlier")
                    Button {
                        move(index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == set.slots.count - 1)
                    .help("Move later")
                    Button(role: .destructive) {
                        update { $0.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .help("Remove")
                }
                if slot.action.kind != .agents {
                    SubRingEditor(slot: slotBinding(index), dropActions: dropActions)
                        .padding(.leading, 24)
                }
            }
        }
        Button("Add an action") { update { $0.append(RingSlot(RingAction(.home))) } }
            .disabled(set.slots.count >= RingSet.maxSlots)
    }

    private func update(_ change: (inout [RingSlot]) -> Void) {
        var slots = set.slots
        change(&slots)
        set.setSlots(slots)
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard set.slots.indices.contains(target) else { return }
        update { $0.swapAt(index, target) }
    }

    private func slotBinding(_ index: Int) -> Binding<RingSlot> {
        Binding(
            get: { set.slots.indices.contains(index) ? set.slots[index] : RingSlot(RingAction(.none)) },
            set: { slot in update { if $0.indices.contains(index) { $0[index] = slot } } })
    }

    private func actionBinding(_ index: Int) -> Binding<RingAction> {
        Binding(
            get: { slotBinding(index).wrappedValue.action },
            set: { action in
                var slot = slotBinding(index).wrappedValue
                slot.action = action
                slotBinding(index).wrappedValue = slot
            })
    }
}

/// The actions that open around a segment.
private struct SubRingEditor: View {
    @Binding var slot: RingSlot
    let dropActions: [DropAction]

    var body: some View {
        ForEach(Array(slot.group.enumerated()), id: \.offset) { index, _ in
            HStack {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                RingActionPicker(action: binding(index), dropActions: dropActions)
                Button(role: .destructive) {
                    var group = slot.group
                    group.remove(at: index)
                    slot = RingSlot(slot.action, group: group)
                } label: {
                    Image(systemName: "minus.circle")
                }
            }
        }
        Button(slot.group.isEmpty ? "Add a sub-ring" : "Add to the sub-ring") {
            slot = RingSlot(slot.action, group: slot.group + [RingAction(.playPause)])
        }
        .buttonStyle(.link)
        .font(.caption)
        .disabled(slot.group.count >= RingSlot.maxSubItems)
    }

    private func binding(_ index: Int) -> Binding<RingAction> {
        Binding(
            get: { slot.group.indices.contains(index) ? slot.group[index] : RingAction(.none) },
            set: { action in
                var group = slot.group
                guard group.indices.contains(index) else { return }
                group[index] = action
                slot = RingSlot(slot.action, group: group)
            })
    }
}

/// Picks an action, with a field for the actions that need a value.
private struct RingActionPicker: View {
    @Binding var action: RingAction
    let dropActions: [DropAction]

    private static let kinds: [RingAction.Kind] = RingAction.Kind.allCases.filter { $0 != .none }

    var body: some View {
        HStack {
            Picker("Action", selection: kind) {
                ForEach(Self.kinds, id: \.self) { kind in
                    Label(RingAction(kind).title, systemImage: RingAction(kind).symbol).tag(kind)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            switch action.kind {
            case .timer:
                Stepper("\(action.minutes) min", value: minutes, in: 1...180)
            case .widget:
                Picker("Widget", selection: value(default: WidgetKind.agents.rawValue)) {
                    ForEach(WidgetKind.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
            case .shortcut:
                TextField("Shortcut name", text: value(default: ""))
            case .dropAction:
                Picker("Drop action", selection: value(default: dropActions.first?.id.uuidString ?? "")) {
                    ForEach(dropActions) { Text($0.name).tag($0.id.uuidString) }
                }
                .labelsHidden()
                .disabled(dropActions.isEmpty)
            default:
                EmptyView()
            }
        }
    }

    private var kind: Binding<RingAction.Kind> {
        Binding(get: { action.kind }, set: { action = RingAction($0) })
    }

    private var minutes: Binding<Int> {
        Binding(get: { action.minutes }, set: { action.value = String($0) })
    }

    private func value(default fallback: String) -> Binding<String> {
        Binding(get: { action.value ?? fallback }, set: { action.value = $0 })
    }
}
