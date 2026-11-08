import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WispCore

struct RingSettings: View {
    @Bindable var preferences: Preferences
    let trigger: RingTrigger
    let hotkeys: HotkeyCenter

    /// The ring being edited: nil for the default ring, else an app's ring.
    @State private var editing: UUID?

    var body: some View {
        Form {
            Section("Opening") {
                if preferences.hotkey.usesHyper {
                    LabeledContent("Hyper key", value: "Hyper+R, at the pointer")
                }
                Toggle("Keyboard shortcut", isOn: hasRingHotkey)
                if preferences.ringHotkey != nil {
                    LabeledContent("Shortcut") { HotkeyRecorder(hotkey: ringHotkey) }
                    if hotkeys.ringHotkeyTaken {
                        Text("Wisp couldn't register this shortcut. Choose another.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Picker("Mouse button", selection: $preferences.ringButton) {
                    ForEach(RingButton.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if preferences.ringButton != .off {
                    LabeledContent("Status", value: trigger.status.message)
                }
                Toggle("Clicking the orb opens the ring", isOn: $preferences.ringOnOrbClick)
                Text(
                    "Hold the mouse button, move to an action and let go, or click it quickly to leave the ring open. Other apps stop seeing the button you choose, and it needs Accessibility. The centre of the ring opens the shelf. Files dragged onto the orb always open the ring, to drop them on an action or on the centre for the tray."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Ring", selection: $editing) {
                    Text("Default").tag(UUID?.none)
                    ForEach(preferences.ringConfig.perApp) { set in
                        Text(set.name).tag(UUID?.some(set.id))
                    }
                }
                RingSetEditor(set: editedSet, dropActions: preferences.dropActions)
                    .id(editing)
                HStack {
                    if let editing {
                        Button("Remove this app's ring", role: .destructive) {
                            preferences.ringConfig.perApp.removeAll { $0.id == editing }
                            self.editing = nil
                        }
                    } else {
                        Button("Reset to the default ring") {
                            preferences.ringConfig.standard = RingConfig.defaults.standard
                        }
                    }
                    Spacer()
                    Button("Add a ring for an app…") { addAppRing() }
                }
            } header: {
                Text("Actions")
            } footer: {
                Text(
                    "Click a segment to change it. An app's ring opens instead of the default while that app is in front."
                )
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

    private var editedSet: Binding<RingSet> {
        Binding(
            get: {
                editing.flatMap { id in preferences.ringConfig.perApp.first { $0.id == id } }
                    ?? preferences.ringConfig.standard
            },
            set: { updated in
                if let editing, let index = preferences.ringConfig.perApp.firstIndex(where: { $0.id == editing }) {
                    preferences.ringConfig.perApp[index] = updated
                } else if editing == nil {
                    preferences.ringConfig.standard = updated
                }
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
        let set = RingSet(name: name, slots: preferences.ringConfig.standard.slots, bundleIDs: [id])
        preferences.ringConfig.perApp.append(set)
        editing = set.id
    }
}

/// A picture of the ring to click segments on, beside an inspector for the selected one.
private struct RingSetEditor: View {
    @Binding var set: RingSet
    let dropActions: [DropAction]

    @State private var selected = 0

    private static let scale: CGFloat = 0.62
    private static let side: CGFloat = RingGeometry.ringOuter * 2 * scale + 12

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 10) {
                preview
                Button("Add an action") {
                    update { $0.append(RingSlot(RingAction(.home))) }
                    selected = set.slots.count - 1
                }
                .disabled(set.slots.count >= RingSet.maxSlots)
            }
            inspector.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var preview: some View {
        let centre = CGPoint(x: Self.side / 2, y: Self.side / 2)
        let slots = set.slots
        return ZStack {
            Circle().fill(Color.black.opacity(0.85))
                .frame(width: Self.side, height: Self.side)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let wedge = RingGeometry.sector(index, count: slots.count)
                RingWedge(
                    start: wedge.start, end: wedge.end, inner: RingGeometry.ringInner * Self.scale,
                    outer: RingGeometry.ringOuter * Self.scale, centre: centre, symbol: slot.action.symbol,
                    fill: index == selected ? .wispViolet : .white.opacity(0.08), dimmed: false,
                    hasMore: !slot.group.isEmpty || slot.action.opensChoices, small: true
                )
            }
            Image("MenuGlyph").resizable().renderingMode(.template).scaledToFit().frame(width: 16, height: 16)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: Self.side, height: Self.side)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
        .contentShape(Circle())
        .onTapGesture(coordinateSpace: .local) { location in
            let up = CGPoint(x: location.x / Self.scale, y: (Self.side - location.y) / Self.scale)
            let middle = CGPoint(x: Self.side / 2 / Self.scale, y: Self.side / 2 / Self.scale)
            if case .slot(let index) = RingGeometry.hit(up, centre: middle, slots: slots.count) { selected = index }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ring preview")
    }

    @ViewBuilder private var inspector: some View {
        if set.slots.indices.contains(selected) {
            let index = selected
            VStack(alignment: .leading, spacing: 10) {
                Text("Segment \(index + 1)").font(.headline)
                RingActionPicker(action: actionBinding(index), dropActions: dropActions)
                if !set.slots[index].action.opensChoices {
                    SubRingEditor(slot: slotBinding(index), dropActions: dropActions)
                } else {
                    Text("Its sub-ring is filled in when the ring opens.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Move earlier") { move(index, by: -1) }.disabled(index == 0)
                    Button("Move later") { move(index, by: 1) }.disabled(index == set.slots.count - 1)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        update { $0.remove(at: index) }
                        selected = max(0, min(selected, set.slots.count - 1))
                    }
                }
            }
        } else {
            Text("No actions yet.").foregroundStyle(.secondary)
        }
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
        selected = target
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
        VStack(alignment: .leading, spacing: 6) {
            Text(slot.group.isEmpty ? "No sub-ring" : "Sub-ring").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(slot.group.enumerated()), id: \.offset) { index, _ in
                HStack {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    RingActionPicker(action: binding(index), dropActions: dropActions)
                    Button(role: .destructive) {
                        var group = slot.group
                        group.remove(at: index)
                        slot.setGroup(group)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from the sub-ring")
                }
            }
            Button(slot.group.isEmpty ? "Add a sub-ring" : "Add to the sub-ring") {
                slot.setGroup(slot.group + [RingAction(.playPause)])
            }
            .disabled(slot.group.count >= RingSlot.maxSubItems)
        }
    }

    private func binding(_ index: Int) -> Binding<RingAction> {
        Binding(
            get: { slot.group.indices.contains(index) ? slot.group[index] : RingAction(.none) },
            set: { action in
                var group = slot.group
                guard group.indices.contains(index) else { return }
                group[index] = action
                slot.setGroup(group)
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
            case .ai:
                Picker("Task", selection: value(default: action.aiTaskID)) {
                    ForEach(AITask.textActions(language: ""), id: \.self) { task in
                        if let id = task.actionID { Text(AITask.actionTitle(id: id) ?? task.title).tag(id) }
                    }
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
        // An AI action always saves its task, so the segment's label matches what it runs.
        Binding(get: { action.kind }, set: { action = RingAction($0, value: $0 == .ai ? "summarise" : nil) })
    }

    private var minutes: Binding<Int> {
        Binding(get: { action.minutes }, set: { action.value = String($0) })
    }

    private func value(default fallback: String) -> Binding<String> {
        Binding(get: { action.value ?? fallback }, set: { action.value = $0 })
    }
}
