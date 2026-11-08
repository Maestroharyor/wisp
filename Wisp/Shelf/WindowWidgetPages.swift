import SwiftUI
import WispCore

/// A widget's row in the shelf window: its full window page where it has one, otherwise the
/// notch layout with a margin. Home's cards use `WidgetCard` directly, so they stay compact.
struct WindowWidgetDetail: View {
    let kind: WidgetKind
    let model: NotchModel

    private var services: AppServices { model.services }

    var body: some View {
        switch kind {
        case .quickToggles:
            QuickTogglesPage(actions: services.quickActions, preferences: services.preferences) {
                services.showSettings(pane: .widgets)
            }
        case .clipboard:
            ClipboardPage(store: services.clipboard, preferences: services.preferences) {
                services.showSettings(pane: .clipboard)
            }
        case .dayProgress: DayProgressPage(calendar: services.calendar, preferences: services.preferences)
        case .worldClocks: WorldClocksPage(preferences: services.preferences)
        case .pomodoro: PomodoroPage(store: services.timers, preferences: services.preferences)
        case .agents:
            AgentsDetail(hub: services.agents, cloud: services.cloud, model: model).padding(20)
        case .quickInput:
            WindowWidgetPage(width: .readable) { _ in
                QuickInputWidget(store: services.quickInput, dictation: services.dictation)
            }
        default:
            WidgetCard(kind: kind, model: model).padding(20)
        }
    }
}

extension AppServices {
    /// Opens Settings on `pane`, also when the window is already open.
    func showSettings(pane: SettingsPaneID) {
        preferences.lastSettingsPane = pane
        openSettings()
    }
}

/// The scaffold for a widget page in the window: content from the top leading corner inside
/// the page margins, scrolling when it runs long. `content` gets the width it has to lay out in.
struct WindowWidgetPage<Content: View>: View {
    enum Width {
        /// Uses the whole detail, for grids.
        case full
        /// Stops at a readable width, for lists and text.
        case readable
    }

    var width: Width = .full
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width
            let inner =
                width == .readable
                ? WindowLayout.readableWidth(available: available) : max(available - 2 * WindowLayout.margin, 0)
            ScrollView(.vertical) {
                content(inner)
                    .frame(width: inner, alignment: .topLeading)
                    .padding(WindowLayout.margin)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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
            .font(.system(size: 13, weight: .semibold))
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
        WindowWidgetPage { width in
            VStack(alignment: .leading, spacing: 12) {
                WindowSectionTitle("States")
                LazyVGrid(columns: windowGridColumns(width: width, minimum: 200), spacing: WindowLayout.spacing) {
                    keepAwakeTile
                    StateTile(
                        symbol: "circle.lefthalf.filled", title: "Dark mode", state: actions.darkMode ? "On" : "Off",
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
                WindowSectionTitle("Actions").padding(.top, 12)
                LazyVGrid(columns: windowGridColumns(width: width, minimum: 160), spacing: WindowLayout.spacing) {
                    ActionTile(symbol: "camera.viewfinder", title: "Screenshot", action: actions.screenshot)
                    ActionTile(symbol: "eyedropper.halffull", title: "Colour picker", action: actions.pickColor)
                    ActionTile(symbol: "lock.fill", title: "Lock screen", action: actions.lockScreen)
                    ActionTile(symbol: "trash.fill", title: "Empty Trash", action: actions.emptyTrash)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Settings for Quick Toggles", systemImage: "gearshape", action: openSettings)
                    .help("Settings for Quick Toggles")
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? Color.wispViolet : .ink.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(on ? Color.white : .ink.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.white : .ink)
                    Text(state)
                        .font(.system(size: 11))
                        .foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondaryText)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.ink.opacity(hovering ? 0.1 : 0.06)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.ink.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.ink.opacity(0.1)))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ink.opacity(hovering ? 0.1 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
