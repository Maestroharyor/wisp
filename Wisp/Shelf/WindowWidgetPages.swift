import SwiftUI
import WispCore

/// A widget's row in the shelf window: its full window page. Home's cards use `WidgetCard`
/// directly, so they and the notch stay compact.
struct WindowWidgetDetail: View {
    let kind: WidgetKind
    let model: NotchModel

    private var services: AppServices { model.services }

    var body: some View {
        switch kind {
        case .quickToggles:
            QuickTogglesPage(actions: services.quickActions, preferences: services.preferences) {
                services.showSettings(pane: .shelf)
            }
        case .clipboard:
            ClipboardPage(store: services.clipboard, preferences: services.preferences) {
                services.showSettings(pane: .shelf)
            }
        case .dayProgress: DayProgressPage(calendar: services.calendar, preferences: services.preferences)
        case .worldClocks: WorldClocksPage(preferences: services.preferences)
        case .pomodoro: PomodoroPage(store: services.timers, preferences: services.preferences)
        case .nowPlaying: WindowMediaPage(model: model)
        case .calendar: CalendarPage(store: services.calendar, preferences: services.preferences)
        case .reminders: RemindersPage(store: services.reminders) { quickAdd("remind me ") }
        case .timer: TimerPage(store: services.timers)
        case .battery:
            BatteryPage(
                monitor: services.battery,
                accessories: services.preferences.accessoryBatteries ? services.accessories.devices : [],
                showsAccessories: services.preferences.accessoryBatteries,
                lowLevel: services.preferences.batteryLowThreshold
            ) {
                services.showSettings(pane: .activities)
            }
        case .systemStats: SystemStatsPage(store: services.stats)
        case .weather: WeatherPage(store: services.weather)
        case .notes: NotesPage(store: services.notes)
        case .shortcuts: ShortcutsPage(runner: services.shortcuts, preferences: services.preferences)
        case .mirror: MirrorPage(camera: services.camera)
        case .script:
            ScriptPage(store: services.script, preferences: services.preferences) {
                services.showSettings(pane: .shelf)
            }
        case .agents: AgentsPage(model: model)
        case .quickInput: QuickAddPage(store: services.quickInput, dictation: services.dictation)
        }
    }

    @Environment(\.openWindowRow) private var openRow

    /// Quick add with the start of the sentence typed, so the rest is a few words.
    private func quickAdd(_ start: String) {
        services.quickInput.text = start
        services.quickInput.requestFocus()
        openRow(.widget(WidgetKind.quickInput.rawValue))
    }
}

// MARK: Agents

/// Agents in the window: the sessions beside the chosen one's detail, under a header that
/// counts what's running and waiting.
private struct AgentsPage: View {
    let model: NotchModel

    var body: some View {
        let hub = model.services.agents
        let running = hub.sessions.list.filter { $0.state == .running }.count
        let waiting = hub.approvals.count
        WindowPageFrame {
            WindowPageHeader(
                symbol: "sparkles", tint: .purple, title: "Agents",
                subtitle: "Claude Code and Codex sessions, their context and what they ask",
                count: waiting > 0 ? "\(waiting) waiting" : "\(running) running")
        } content: {
            AgentsDetail(hub: hub, cloud: model.services.cloud, model: model)
        }
    }
}

// MARK: Quick add

/// Quick add in the window: a large field, then examples to start from.
private struct QuickAddPage: View {
    let store: QuickInputStore
    let dictation: DictationEngine

    private static let examples = [
        "coffee with Maya friday 9:30am", "remind me to water the plants tomorrow", "dentist next tuesday 4pm",
        "call mom tonight", "timer 25 min", "team sync monday 10am",
    ]

    var body: some View {
        WindowWidgetPage(width: .readable) {
            WindowPageHeader(
                symbol: "text.badge.plus", tint: .pink, title: "Quick add",
                subtitle: "Type it the way you'd say it. Wisp adds it to Calendar, Reminders or a timer.")
        } content: { _ in
            VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                QuickInputWidget(store: store, dictation: dictation)
                    .padding(16)
                    .frame(minHeight: 150)
                    .windowCardBackground()
                WindowCard(title: "Try one", symbol: "lightbulb", tint: .yellow) {
                    FlowChips(items: Self.examples) { example in
                        store.text = example
                        store.requestFocus()
                    }
                }
            }
        }
    }
}

/// Tappable example phrases that wrap onto as many lines as they need.
private struct FlowChips: View {
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    pick(item)
                } label: {
                    Text(item)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .wispHover(shape: Capsule())
                        .background(Capsule().fill(.primary.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Use this example")
            }
        }
    }
}

/// Lays its children out left to right, starting a new line when one doesn't fit.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var xs: [CGFloat] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            let x = row.indices.isEmpty ? 0 : row.width + spacing
            row.indices.append(index)
            row.xs.append(x)
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

extension AppServices {
    /// Opens Settings on `pane`, also when the window is already open.
    func showSettings(pane: SettingsPaneID) {
        preferences.lastSettingsPane = pane
        openSettings()
    }
}

/// Reminders in the window: tiles that count and filter, then the open reminders in a card.
/// Rows tick off, undo and drag as on the shelf's card.
struct RemindersPage: View {
    let store: RemindersStore
    let newReminder: () -> Void
    @State private var filter: ReminderFilter = .all
    /// The Reminders list chosen in the Lists column; nil is every list.
    @State private var list: String?

    var body: some View {
        WindowWidgetPage(width: .full) {
            WindowPageHeader(
                symbol: "checklist", tint: .orange, title: "Reminders", subtitle: "Your open reminders, overdue first"
            ) {
                Button("Open Reminders", systemImage: "arrow.up.forward.app", action: store.openApp)
                    .labelStyle(.iconOnly)
                    .help("Open Reminders")
                WindowPrimaryButton(title: "New reminder", symbol: "plus", action: newReminder)
            }
        } content: { width in
            VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                if store.access == .fullAccess {
                    tiles(width: width)
                    if WindowLayout.masterDetail(width: width) {
                        HStack(alignment: .top, spacing: WindowLayout.spacing) {
                            lists.frame(width: 240)
                            reminders
                        }
                    } else {
                        reminders
                    }
                } else {
                    reminders
                }
            }
        }
        .onAppear { store.refreshIfStale() }
    }

    private func tiles(width: CGFloat) -> some View {
        let now = Date.now
        return LazyVGrid(
            columns: windowGridColumns(width: width, minimum: 150), spacing: WindowLayout.spacing
        ) {
            ForEach(ReminderFilter.allCases) { item in
                WindowStatTile(
                    value: item.count(store.items, now: now), label: item.title, symbol: symbol(item),
                    tint: tint(item), selected: filter == item
                ) { filter = item }
            }
        }
    }

    private var lists: some View {
        WindowCard(title: "Lists", symbol: "list.bullet", tint: .gray, minHeight: 320) {
            VStack(alignment: .leading, spacing: 2) {
                listRow(name: "All lists", color: .wispViolet, count: store.items.count, selected: list == nil) {
                    list = nil
                }
                ForEach(ReminderListSummary.summaries(store.items)) { summary in
                    listRow(
                        name: summary.name, color: summary.color.map(Color.init(rgb:)) ?? .gray, count: summary.count,
                        selected: list == summary.name
                    ) { list = summary.name }
                }
            }
        }
    }

    private func listRow(name: String, color: Color, count: Int, selected: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 14, height: 14)
                Text(name).font(.body).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(Color.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .wispHover(cornerRadius: SurfaceRadius.row)
            .background(
                RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                    .fill(selected ? Color.wispViolet.opacity(0.22) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var reminders: some View {
        let shown = filter.apply(store.items, now: .now).filter { list == nil || $0.list == list }
        WindowCard(
            title: list ?? (filter == .all ? "Open" : filter.title), symbol: symbol(filter), tint: tint(filter),
            count: store.access == .fullAccess ? shown.count : nil, minHeight: 320
        ) {
            if store.access != .fullAccess {
                WindowEmptyState(
                    symbol: "checklist", title: "Reminders access needed",
                    message: "Allow Reminders to see your open reminders here and tick them off."
                ) {
                    WindowPrimaryButton(title: "Allow Reminders", symbol: "lock.open") { store.requestAccess() }
                }
            } else if !store.loaded, !store.failed, store.items.isEmpty {
                LoadingLabel("Loading…").frame(minHeight: 160)
            } else if shown.isEmpty {
                WindowEmptyState(
                    symbol: store.failed ? "exclamationmark.triangle" : "checkmark.circle",
                    title: store.failed ? "Couldn't read Reminders" : "All done",
                    message: store.failed
                        ? "Try again in a moment, or open the Reminders app."
                        : filter == .all && list == nil
                            ? "Nothing open. Add one with New reminder." : "Nothing here right now."
                ) {
                    if store.failed {
                        WindowPrimaryButton(title: "Try again", symbol: "arrow.clockwise") { store.refresh() }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 28) }
                        HStack(spacing: 8) {
                            ReminderRow(item: item, done: store.justDone.contains(item.id), store: store)
                            if !item.list.isEmpty, list == nil {
                                Text(item.list)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(item.listColor.map(Color.init(rgb:)) ?? Color.secondaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(
                                            (item.listColor.map(Color.init(rgb:)) ?? .gray).opacity(0.15)))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func symbol(_ filter: ReminderFilter) -> String {
        switch filter {
        case .all: "tray.full.fill"
        case .today: "calendar"
        case .overdue: "exclamationmark.circle.fill"
        case .scheduled: "clock.fill"
        }
    }

    private func tint(_ filter: ReminderFilter) -> Color {
        switch filter {
        case .all: .wispViolet
        case .today: .blue
        case .overdue: .red
        case .scheduled: .orange
        }
    }
}

/// A section heading on a window page.
struct WindowSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Equal columns for a card grid `width` wide, as many as `WindowLayout` fits.
func windowGridColumns(width: CGFloat, minimum: CGFloat = WindowLayout.cardMinimum) -> [GridItem] {
    let count = WindowLayout.columns(width: width, minimum: minimum)
    return Array(repeating: GridItem(.flexible(), spacing: WindowLayout.spacing), count: count)
}

// MARK: Quick Toggles

/// Quick Toggles in the window: states as large tiles, one-off actions as buttons below.
struct QuickTogglesPage: View {
    let actions: QuickActions
    let preferences: Preferences
    let openSettings: () -> Void

    @State private var pickingTime = false
    @State private var untilTime = Date.now.addingTimeInterval(3600)

    var body: some View {
        WindowWidgetPage {
            WindowPageHeader(
                symbol: "switch.2", tint: .indigo, title: "Quick Toggles",
                subtitle: "Switch Mac settings and run one-off actions"
            ) {
                Button("Settings for Quick Toggles", systemImage: "gearshape", action: openSettings)
                    .labelStyle(.iconOnly)
                    .help("Settings for Quick Toggles")
            }
        } content: { width in
            VStack(alignment: .leading, spacing: WindowLayout.spacing) {
                WindowCard(title: "States", symbol: "power", tint: .wispViolet) {
                    LazyVGrid(columns: windowGridColumns(width: width - 32, minimum: 200), spacing: 12) {
                        keepAwakeTile
                        StateTile(
                            symbol: "circle.lefthalf.filled", title: "Dark mode",
                            state: actions.darkMode ? "On" : "Off",
                            on: actions.darkMode, action: actions.toggleDarkMode)
                        StateTile(
                            symbol: "eye.slash.fill", title: "Hide desktop icons",
                            state: actions.desktopHidden ? "On" : "Off", on: actions.desktopHidden,
                            action: actions.toggleDesktopIcons)
                        // macOS has no public Focus API, so there's no state to show.
                        StateTile(
                            symbol: "moon.fill", title: "Focus",
                            state: preferences.doNotDisturbShortcut.isEmpty
                                ? "Choose a Shortcut in Settings" : "Runs your Shortcut",
                            on: false, action: actions.toggleDoNotDisturb)
                    }
                }
                WindowCard(title: "Actions", symbol: "bolt.fill", tint: .orange) {
                    LazyVGrid(columns: windowGridColumns(width: width - 32, minimum: 160), spacing: 12) {
                        ActionTile(symbol: "camera.viewfinder", title: "Screenshot", action: actions.screenshot)
                        ActionTile(symbol: "eyedropper.halffull", title: "Colour picker", action: actions.pickColor)
                        ActionTile(symbol: "lock.fill", title: "Lock screen", action: actions.lockScreen)
                        ActionTile(symbol: "trash.fill", title: "Empty Trash", action: actions.emptyTrash)
                    }
                }
            }
        }
        .onAppear { actions.refresh() }
    }

    private var keepAwakeTile: some View {
        StateTile(
            symbol: "cup.and.saucer.fill", title: "Keep awake", state: keepAwakeState, on: actions.keepAwake,
            action: actions.toggleKeepAwake
        ) {
            Menu {
                Button("Indefinitely") { actions.startKeepAwake(.lasting(nil, from: .now)) }
                Button("For 1 hour") { actions.startKeepAwake(.lasting(3600, from: .now)) }
                Button("For 2 hours") { actions.startKeepAwake(.lasting(2 * 3600, from: .now)) }
                Button("Until…") {
                    untilTime = actions.keepAwakeSession?.ends ?? Date.now.addingTimeInterval(3600)
                    pickingTime = true
                }
                if actions.keepAwake {
                    Divider()
                    Button("Turn off", action: actions.endKeepAwake)
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Keep awake for")
            .accessibilityLabel("Keep awake for")
            .popover(isPresented: $pickingTime, arrowEdge: .bottom) { untilPicker }
        }
    }

    private var keepAwakeState: String {
        guard actions.keepAwake else { return "Off" }
        guard let ends = actions.keepAwakeSession?.ends else { return "On" }
        return "Until \(ends.formatted(date: .omitted, time: .shortened))"
    }

    private var untilPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Keep awake until", selection: $untilTime, displayedComponents: .hourAndMinute)
            HStack {
                Spacer()
                Button("Cancel") { pickingTime = false }
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: untilTime)
                    actions.startKeepAwake(.until(hour: parts.hour ?? 0, minute: parts.minute ?? 0, from: .now))
                    pickingTime = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

/// A large state tile: icon, name and a state line, filled Wisp violet while on. `accessory`
/// sits in the top trailing corner (Keep awake's duration menu).
private struct StateTile<Accessory: View>: View {
    let symbol: String
    let title: String
    let state: String
    let on: Bool
    let action: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(on ? Color.wispViolet : .ink.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(on ? Color.white : .ink.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(on ? Color.white : .ink)
                    Text(state)
                        .font(.subheadline)
                        .foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondaryText)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous)
                    .fill(on ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.ink.opacity(hovering ? 0.1 : 0.06)))
            )
            .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(state)
        .accessibilityAddTraits(on ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            accessory()
                .foregroundStyle(on ? Color.white : .ink.opacity(0.7))
                .padding(10)
        }
        .onHover { hovering = $0 }
    }
}

extension StateTile where Accessory == EmptyView {
    init(symbol: String, title: String, state: String, on: Bool, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, state: state, on: on, action: action) { EmptyView() }
    }
}

/// A one-off action as a button with an icon and a name.
private struct ActionTile: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.ink.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.ink.opacity(0.1)))
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: SurfaceRadius.row + 2, style: .continuous).fill(
                    .ink.opacity(hovering ? 0.1 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.row + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
