import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// The Ring pane: how the ring opens, the orb's part in it, and a button for the segment editor.
/// Its keyboard shortcut is in the Shortcuts pane with the rest.
struct RingSettings: View {
    @Bindable var preferences: Preferences
    let trigger: RingTrigger
    let openShortcuts: () -> Void

    @State private var editorShown = false
    /// The ring's colour, starting from a dark violet the first time one is picked.
    private var ringColour: Binding<RGB> {
        Binding(
            get: { preferences.ringLook.colour ?? RGB(red: 0.16, green: 0.13, blue: 0.3) },
            set: { preferences.ringLook.colour = $0 })
    }

    /// The orb dock's own apps, in order, with Add (up to eight) and remove.
    @ViewBuilder private var chosenApps: some View {
        let names = AppNames.names(for: preferences.orbDockApps)
        ForEach(preferences.orbDockApps, id: \.self) { id in
            HStack(spacing: 8) {
                RingTileIcon(icon: .app(bundleID: id), tileHex: "#8E8E93", side: 20)
                Text(names[id] ?? id).lineLimit(1)
                Spacer()
                Button {
                    preferences.orbDockApps.removeAll { $0 == id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(names[id] ?? id)")
            }
        }
        HStack {
            Spacer()
            Button("Add app…", action: addDockApp)
                .disabled(preferences.orbDockApps.count >= RingDock.size)
        }
    }

    private func addDockApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !preferences.orbDockApps.contains(id),
                preferences.orbDockApps.count < RingDock.size
            else { continue }
            preferences.orbDockApps.append(id)
        }
    }

    /// Read when the pane shows; macOS doesn't announce a change.
    @State private var canPreview = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            if !preferences.ringTipsHidden {
                RingTipsSection(preferences: preferences)
            }
            Section {
                Picker("Mouse button", selection: $preferences.ringButton) {
                    ForEach(RingButton.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if preferences.ringButton != .off {
                    LabeledContent("Status", value: trigger.status.message)
                }
                Toggle("Clicking the orb opens the ring", isOn: $preferences.ringOnOrbClick)
                LabeledContent("Keyboard shortcut") {
                    Button("Shortcuts…", action: openShortcuts)
                }
                if preferences.ringTipsHidden {
                    LabeledContent("Try the ring") {
                        Button("Show checklist") { preferences.ringTipsHidden = false }
                    }
                }
            } header: {
                SettingsHeader("Opening")
            } footer: {
                Text(
                    "Hold the mouse button, move to an action and let go, or click to leave the ring open (needs Accessibility). Dragging files? Press the ring shortcut and drop them on an action."
                )
            }
            Section {
                Picker("Background", selection: $preferences.ringLook.backdrop) {
                    ForEach(RingBackdrop.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Glass", selection: $preferences.ringLook.glass) {
                    ForEach(PanelGlass.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(preferences.ringLook.backdrop == .orbit)
                LabeledContent("Colour") {
                    HStack {
                        if preferences.ringLook.colour != nil {
                            Button("Default glass") { preferences.ringLook.colour = nil }
                        }
                        ColorPicker("Colour", selection: ringColour.color, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                if preferences.ringLook.colour != nil {
                    LabeledContent("Colour strength") {
                        Slider(value: $preferences.ringLook.colourAmount, in: 0...1)
                    }
                }
                Picker("Centre", selection: $preferences.ringLook.centre) {
                    ForEach(RingCentre.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $preferences.ringLook.size, in: RingLook.sizeRange, step: 0.05)
                        Text("\(Int((preferences.ringLook.size * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Violet tint") {
                    Slider(value: $preferences.ringLook.tint, in: 0...1)
                }
                HStack {
                    Spacer()
                    Button("Reset look") { preferences.ringLook = .standard }
                        .disabled(preferences.ringLook == .standard)
                }
            } header: {
                SettingsHeader("Look")
            } footer: {
                Text(
                    "Frosted glass is easiest to read over busy windows. Colour tints the band and a Frosted or Tinted centre. Reduce Transparency makes the ring solid."
                )
            }
            Section {
                LabeledContent("Add to the ring") {
                    RingAddMenu(set: $preferences.ringConfig.standard)
                }
                LabeledContent("Segments") {
                    Button("Edit ring…") { editorShown = true }
                        // On the button, not the Section: a Form can apply a Section's modifiers per row.
                        .sheet(isPresented: $editorShown) {
                            RingEditorSheet(preferences: preferences) { editorShown = false }
                        }
                }
                Toggle("Show an app's windows around its segment", isOn: $preferences.ringAppWindows)
                if preferences.ringAppWindows, !canPreview {
                    LabeledContent("Window previews need Screen Recording") {
                        Button("Open Settings…") { Permission.screenRecording.openSettings() }
                    }
                }
                Toggle("Fill free places with running apps", isOn: $preferences.ringShowsRunning)
            } header: {
                SettingsHeader("Apps and actions")
            } footer: {
                Text(
                    "On the open ring, drag an icon to move it, off the ring to remove it (⌘Z puts it back), or drop an app from Finder to add it."
                )
            }
            Section {
                Toggle("Show apps beside the orb", isOn: $preferences.orbDock)
                if preferences.orbDock {
                    Picker("Apps", selection: $preferences.orbDockSource) {
                        ForEach(OrbDockSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if preferences.orbDockSource == .chosen { chosenApps }
                }
            } header: {
                SettingsHeader("Orb dock")
            } footer: {
                Text("Hovering the orb shows up to eight apps beside it, to click or drop files on.")
            }
        }
        .formStyle(.grouped)
        .onAppear { canPreview = CGPreflightScreenCaptureAccess() }
    }
}

/// "Try the ring": the ring's gestures as a checklist that ticks itself off as they're used.
private struct RingTipsSection: View {
    @Bindable var preferences: Preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var canPreview = CGPreflightScreenCaptureAccess()

    /// What showing windows needs that this Mac doesn't have yet.
    private var windowsNeed: String? {
        if !preferences.ringAppWindows { return "Turn on \u{201C}Show an app's windows\u{201D} below." }
        if !AccessibilityPermission.isTrusted { return "Needs Accessibility, to list the app's windows." }
        if !canPreview { return "The app's windows fan out; live previews also need Screen Recording." }
        return nil
    }

    var body: some View {
        let tips = preferences.ringTips
        Section {
            ForEach(RingTips.Step.allCases) { step in
                let done = tips.done.contains(step)
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(done ? Color.wispViolet : Color.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .foregroundStyle(done ? .secondary : .primary)
                            .strikethrough(done, color: .secondary)
                        if step == .windows, !done, let need = windowsNeed {
                            Text(need).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if step == .windows, !done, !canPreview {
                        Button("Screen Recording…") { Permission.screenRecording.openSettings() }
                            .controlSize(.small)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(done ? "Done" : "Not yet")
            }
            HStack {
                if tips.isComplete {
                    Label("All done", systemImage: "sparkles").foregroundStyle(Color.wispViolet)
                } else {
                    Text("\(tips.done.count) of \(RingTips.Step.allCases.count)").foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if !tips.done.isEmpty {
                    Button("Start over") { preferences.ringTips.reset() }
                }
                Button("Hide") { preferences.ringTipsHidden = true }
            }
        } header: {
            SettingsHeader("Try the ring")
        }
        .animation(reduceMotion ? nil : .wispSmooth, value: tips)
    }
}

/// The segment editor, in a sheet. Changes apply as they're made, so Done (or Esc) only closes
/// it. Done doesn't take Return, which belongs to the Shortcut name field.
private struct RingEditorSheet: View {
    @Bindable var preferences: Preferences
    let done: () -> Void

    /// The ring being edited: nil for the default ring, else an app's ring.
    @State private var editing: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Form {
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
                    LabeledContent("Add to this ring") {
                        RingAddMenu(set: editedSet)
                    }
                } header: {
                    SettingsHeader("Ring actions")
                } footer: {
                    Text(
                        "Click a segment to change it. The centre of the ring opens the shelf. An app's ring opens instead of the default while that app is in front."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 440, idealHeight: 560)
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
        // An app has one ring; a second would never be used, since the first match wins.
        if let existing = preferences.ringConfig.perApp.first(where: { $0.bundleIDs.contains(id) }) {
            editing = existing.id
            return
        }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        let slots = preferences.ringConfig.standard.slots.map { RingSlot($0.action, group: $0.group) }
        let set = RingSet(name: name, slots: slots, bundleIDs: [id])
        preferences.ringConfig.perApp.append(set)
        editing = set.id
    }
}

/// A picture of the ring to click segments on, beside an inspector for the selected one.
private struct RingSetEditor: View {
    @Binding var set: RingSet
    let dropActions: [DropAction]

    @State private var selected = 0
    @Environment(\.colorScheme) private var colorScheme

    private static let scale: CGFloat = 0.62
    private static let side: CGFloat = (RingGeometry.ringOuter + 8) * 2 * scale

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
            // The ring's own background, drawn at full size and scaled, so it follows the Look
            // settings as they change; the trail points at the selected segment.
            let full = Self.side / Self.scale
            RingDisc(
                centre: CGPoint(x: full / 2, y: full / 2), dark: colorScheme == .dark, shown: true,
                hoverAngle: slots.isEmpty ? nil : RingGeometry.slotAngle(selected, count: slots.count),
                reduceMotion: true
            )
            .frame(width: full, height: full)
            .scaleEffect(Self.scale)
            .frame(width: Self.side, height: Self.side)
            .allowsHitTesting(false)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let angle = RingGeometry.slotAngle(index, count: slots.count)
                let radians = angle * .pi / 180
                let radius = RingGeometry.ringRadius * Self.scale
                RingIconCell(
                    icon: slot.action.icon, tileHex: slot.action.tileHex, side: RingGeometry.iconSize * Self.scale,
                    angle: angle, lit: index == selected, dimmed: false,
                    hasMore: !slot.group.isEmpty || slot.action.opensChoices
                )
                .position(x: centre.x + radius * sin(radians), y: centre.y - radius * cos(radians))
            }
            Image("MenuGlyph").resizable().renderingMode(.template).scaledToFit().frame(width: 16, height: 16)
                .foregroundStyle(Color.wispViolet.opacity(0.75))
        }
        .frame(width: Self.side, height: Self.side)
        .animation(.wispControl, value: selected)
        .contentShape(Circle())
        .onTapGesture(coordinateSpace: .local) { location in
            let up = CGPoint(x: location.x / Self.scale, y: (Self.side - location.y) / Self.scale)
            let middle = CGPoint(x: Self.side / 2 / Self.scale, y: Self.side / 2 / Self.scale)
            if case .slot(let index) = RingGeometry.hit(up, centre: middle, slots: slots.count) { selected = index }
        }
        // VoiceOver picks a segment by swiping up or down on the picture.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ring segments")
        .accessibilityValue(
            slots.indices.contains(selected)
                ? "Segment \(selected + 1) of \(slots.count), \(slots[selected].action.title)" : "Empty"
        )
        .accessibilityAdjustableAction { direction in
            guard !slots.isEmpty else { return }
            switch direction {
            case .increment: selected = (selected + 1) % slots.count
            case .decrement: selected = (selected - 1 + slots.count) % slots.count
            @unknown default: break
            }
        }
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
                    .accessibilityLabel("Remove from the sub-ring")
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
                Picker("Widget", selection: widget) {
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
            case .app:
                Button(action.value == nil ? "Choose app…" : "Change…") { chooseApp() }
            case .link:
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Address", text: value(default: ""), prompt: Text("example.com"))
                    TextField("Name", text: label, prompt: Text(action.title))
                    if let link = action.value, !link.isEmpty, RingLinks.normalised(link) == nil {
                        Text("Wisp can't open this link.").font(.caption).foregroundStyle(.orange)
                    }
                }
            case .folder:
                Button(action.value == nil ? "Choose folder…" : "Change…") { chooseFolder() }
            default:
                EmptyView()
            }
        }
    }

    private var label: Binding<String> {
        Binding(get: { action.label ?? "" }, set: { action.label = $0.isEmpty ? nil : $0 })
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        action = RingAction(.app, value: id, label: name)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL =
            action.value.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action = RingAction(.folder, value: url.path)
    }

    private var kind: Binding<RingAction.Kind> {
        // Actions with a picker save what the picker shows, so the segment runs what it says.
        // Picking the same kind again keeps the app, link or folder already chosen.
        Binding(
            get: { action.kind },
            set: { kind in
                guard kind != action.kind else { return }
                switch kind {
                case .ai: action = RingAction(.ai, value: "summarise")
                case .widget:
                    action = RingAction(.widget, value: WidgetKind.agents.rawValue, label: WidgetKind.agents.title)
                case .dropAction: action = RingAction(.dropAction, value: dropActions.first?.id.uuidString)
                default: action = RingAction(kind)
                }
            })
    }

    /// The widget and its name, so the segment and type to find show "Day progress", not an id.
    private var widget: Binding<String> {
        Binding(
            get: { action.value ?? WidgetKind.agents.rawValue },
            set: {
                action.value = $0
                action.label = WidgetKind(rawValue: $0)?.title
            })
    }

    private var minutes: Binding<Int> {
        Binding(get: { action.minutes }, set: { action.value = String($0) })
    }

    private func value(default fallback: String) -> Binding<String> {
        Binding(get: { action.value ?? fallback }, set: { action.value = $0 })
    }
}

/// Adds an app, a website or link, or a folder to a ring, after the segments already on it.
/// A full ring (twelve segments) or something already on it says so instead.
struct RingAddMenu: View {
    @Binding var set: RingSet

    @State private var addingLink = false
    @State private var address = ""
    @State private var name = ""
    @State private var message: String?

    var body: some View {
        HStack(spacing: 8) {
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Menu("Add…") {
                Button("App…", systemImage: "app") { chooseApp() }
                Button("Website or link…", systemImage: "globe") {
                    address = ""
                    name = ""
                    addingLink = true
                }
                Button("Folder…", systemImage: "folder") { chooseFolder() }
            }
            .fixedSize()
            .disabled(set.slots.count >= RingSet.maxSlots)
            .help(set.slots.count >= RingSet.maxSlots ? "The ring is full. Remove a segment first." : "Add to the ring")
        }
        .sheet(isPresented: $addingLink) { linkSheet }
    }

    private var linkSheet: some View {
        let url = RingLinks.normalised(address)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Add a website or link").font(.title3.bold())
            Text("A web address such as example.com, or an app link such as slack://open or mailto:hi@example.com.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                TextField("Address", text: $address, prompt: Text("example.com"))
                TextField("Name", text: $name, prompt: Text(url?.host() ?? "Optional"))
            }
            .formStyle(.grouped)
            if !address.isEmpty, url == nil {
                Text("Wisp can't open this address.").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { addingLink = false }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let url else { return }
                    add(RingAction(.link, value: url.absoluteString, label: name.isEmpty ? nil : name))
                    addingLink = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let apps = panel.urls.compactMap { url -> RingAction? in
            guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            return RingAction(.app, value: id, label: name)
        }
        add(apps)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(RingAction(.folder, value: url.path))
    }

    private func add(_ action: RingAction) { add([action]) }

    private func add(_ actions: [RingAction]) {
        guard !actions.isEmpty else { return }
        switch RingArrange.insert(actions, into: set.slots, at: set.slots.count) {
        case .added(let slots):
            set.setSlots(slots)
            message = actions.count == 1 ? "Added \(actions[0].title)" : "Added \(actions.count) apps"
        case .alreadyThere: message = "Already on the ring"
        case .full: message = "The ring is full"
        }
    }
}
