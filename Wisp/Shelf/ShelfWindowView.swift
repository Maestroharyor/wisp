import Observation
import SwiftUI
import WispCore

/// Where the shelf's pages are drawn. Under the shell they keep their fixed notch sizes; in
/// the window they fill the space they're given.
enum ShelfHost {
    case notch
    case window
}

/// Opens a row of the shelf window's sidebar, for views inside it (Home's cards).
struct OpenWindowRow {
    let action: @MainActor (WindowDestination) -> Void

    @MainActor func callAsFunction(_ destination: WindowDestination) { action(destination) }
}

extension EnvironmentValues {
    @Entry var shelfHost: ShelfHost = .notch
    @Entry var openWindowRow = OpenWindowRow { _ in }
}

/// The shelf window's sidebar selection, kept in Preferences so the window reopens where it was.
@MainActor
@Observable
final class WindowNavigation {
    private let preferences: Preferences
    /// A widget opened that isn't switched on (a timer pill, say): listed until it's left.
    private(set) var visitor: String?
    var columns: NavigationSplitViewVisibility = .all

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Selects `destination`, the way pills, menus and tearing off ask for a row.
    func open(_ destination: WindowDestination) {
        if case .widget(let id) = destination, !preferences.enabledWidgets.map(\.rawValue).contains(id) {
            visitor = id
        } else {
            visitor = nil
        }
        preferences.windowSelection = destination.rawValue
    }

    /// Selects a row the sidebar lists, leaving any visitor behind.
    func select(_ destination: WindowDestination) {
        if destination != visitor.map(WindowDestination.widget) { visitor = nil }
        if preferences.windowSelection != destination.rawValue { preferences.windowSelection = destination.rawValue }
    }

    /// The live activities that are running. Reads only whether each runs, so the window
    /// doesn't redraw on every download or activity progress tick.
    func live(services: AppServices) -> [WindowLive] {
        var live: [WindowLive] = []
        if services.regionWatch.appName != nil { live.append(.regionWatch) }
        if services.downloads.hasDownloads { live.append(.downloads) }
        if services.automation.hasCurrent { live.append(.external) }
        return live
    }

    func sections(services: AppServices) -> [WindowSidebarSection] {
        WindowSidebar.sections(
            enabledWidgets: preferences.enabledWidgets.map(\.rawValue),
            gridOrder: preferences.gridWidgets.map(\.rawValue), live: live(services: services), visiting: visitor)
    }

    /// The saved row while the sidebar lists it, otherwise Home.
    func selection(in sections: [WindowSidebarSection]) -> WindowDestination {
        WindowSidebar.resolve(preferences.windowSelection.flatMap(WindowDestination.init(rawValue:)), in: sections)
    }

    func perform(_ action: WindowKeys.Action) {
        switch action {
        case .select(let page): select(.page(page))
        case .toggleSidebar: columns = columns == .detailOnly ? .all : .detailOnly
        }
    }
}

extension WindowDestination {
    /// The row a shelf view opens on. The Widgets page opens its first widget.
    init(_ view: ShelfView, gridWidgets: [WidgetKind]) {
        switch view {
        case .page(let page):
            self = WindowSidebar.destination(forPage: page.name, gridWidgets: gridWidgets.map(\.rawValue))
        case .widget(let kind):
            self = .widget(kind.rawValue)
        case .detail(let detail):
            self = .live(detail.live)
        }
    }
}

extension ActivityDetail {
    var live: WindowLive {
        switch self {
        case .regionWatch: .regionWatch
        case .downloads: .downloads
        case .external: .external
        }
    }
}

/// The shelf window: a sidebar of pages, widgets and live activities, and the chosen one
/// filling the rest. Follows the system's Light or Dark mode.
/// The root reads only what picks the selection (preferences and whether each live activity
/// runs); rows, titles and pages are in their own views.
struct ShelfWindowView: View {
    let model: NotchModel
    @Bindable var navigation: WindowNavigation

    var body: some View {
        let selection = navigation.selection(in: navigation.sections(services: model.services))
        NavigationSplitView(columnVisibility: $navigation.columns) {
            WindowSidebarList(model: model, navigation: navigation, selection: selection)
        } detail: {
            WindowDetail(model: model, navigation: navigation, selection: selection)
        }
        .tint(Color.wispViolet)
        .environment(\.valueFont, model.preferences.appearance.valueFont)
        .onChange(of: selection, initial: true) { _, row in
            // A row that went away (a widget switched off, an activity ended) fell back to Home;
            // save that, so the window doesn't jump back if the row returns.
            navigation.select(row)
            // Customising is for Home; leaving it ends with the changes kept, as closing the
            // notch's shelf does.
            if row != .home, model.editingHome { model.endHomeEditing() }
        }
    }
}

/// The selected row's page, with its title and toolbar.
private struct WindowDetail: View {
    let model: NotchModel
    let navigation: WindowNavigation
    let selection: WindowDestination

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var services: AppServices { model.services }

    var body: some View {
        detail(selection)
            .navigationTitle(WindowRow.title(of: selection, services: services))
            .toolbar { toolbar(selection) }
    }

    private func detail(_ selection: WindowDestination) -> some View {
        ZStack {
            // Out of the view tree while hidden, so cameras and pollers stop.
            if model.phase == .open {
                page(selection)
                    .id(selection)
                    .transition(.opacity)
            }
        }
        // Swaps right away, like Notes or Music; a short fade unless Reduce Motion is on.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let hub = services.agents
            if let approval = hub.approvals.first {
                ApprovalBar(approval: approval, hub: hub, model: model)
                    .id(approval.id)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .hoverHintHost()
        .environment(\.shelfHost, .window)
        .environment(\.openWindowRow, OpenWindowRow { [navigation] in navigation.select($0) })
    }

    @ViewBuilder private func page(_ destination: WindowDestination) -> some View {
        switch destination {
        case .page(.home): HomePage(model: model)
        case .page(.tray): TrayPage(model: model)
        case .page(.media): MediaPage(model: model)
        case .widget(let id):
            if let kind = WidgetKind(rawValue: id) {
                Group {
                    if kind == .agents {
                        AgentsDetail(hub: services.agents, cloud: services.cloud, model: model)
                    } else {
                        WidgetCard(kind: kind, model: model)
                    }
                }
                .padding(20)
            }
        case .live(let live):
            Group {
                switch live {
                case .regionWatch: RegionWatchDetail(watch: services.regionWatch)
                case .downloads: DownloadsDetail(monitor: services.downloads)
                case .external: ExternalActivityDetail(automation: services.automation)
                }
            }
            .padding(24)
        }
    }

    @ToolbarContentBuilder private func toolbar(_ selection: WindowDestination) -> some ToolbarContent {
        if selection == .home {
            ToolbarItem(placement: .primaryAction) {
                Button("Customise Home", systemImage: "square.grid.2x2") {
                    model.homeSnapshot = (
                        model.preferences.homeLayout, model.preferences.enabledWidgets, model.preferences.homeProfile
                    )
                    model.editingHome = true
                }
                .disabled(model.editingHome)
                .help("Customise Home")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                FormMenuItems(model: model)
            } label: {
                Label("Form", systemImage: model.form.symbol)
            }
            .help("Change form")
        }
    }
}

/// The sidebar on its own, so badge and row changes redraw only the list.
private struct WindowSidebarList: View {
    let model: NotchModel
    let navigation: WindowNavigation
    let selection: WindowDestination

    private var services: AppServices { model.services }

    var body: some View {
        List(
            selection: Binding<WindowDestination?>(
                get: { selection },
                set: { if let row = $0 { navigation.select(row) } })
        ) {
            ForEach(navigation.sections(services: services)) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.self) { row in
                        WindowSidebarRow(row: row, services: services)
                            .badge(badge(of: row))
                            .tag(row)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    private func badge(of row: WindowDestination) -> Int {
        switch row {
        case .page(.tray): services.tray.count
        case .widget(WidgetKind.agents.rawValue): services.agents.approvals.count
        default: 0
        }
    }
}

/// One row's label on its own, so an outside activity's progress redraws only its row.
private struct WindowSidebarRow: View {
    let row: WindowDestination
    let services: AppServices

    var body: some View {
        Label {
            Text(WindowRow.title(of: row, services: services))
        } icon: {
            IconTile(symbol: WindowRow.symbol(of: row, services: services), tint: WindowRow.tint(of: row))
        }
    }
}

/// How each sidebar row is labelled.
@MainActor
private enum WindowRow {
    static func title(of row: WindowDestination, services: AppServices) -> String {
        switch row {
        case .page(.home): "Home"
        case .page(.tray): "Tray"
        case .page(.media): "Media"
        case .widget(let id): WidgetKind(rawValue: id)?.title ?? id
        case .live(.regionWatch): services.regionWatch.appName.map { "Watching \($0)" } ?? "Region watch"
        case .live(.downloads): "Downloads"
        case .live(.external): services.automation.current?.title ?? "Activity"
        }
    }

    static func symbol(of row: WindowDestination, services: AppServices) -> String {
        switch row {
        case .page(.home): "house.fill"
        case .page(.tray): "tray.fill"
        case .page(.media): "music.note"
        case .widget(let id): WidgetKind(rawValue: id)?.symbol ?? "square.grid.2x2"
        case .live(.regionWatch): "eye"
        case .live(.downloads): "arrow.down"
        case .live(.external): services.automation.current?.symbol ?? "bolt.fill"
        }
    }

    static func tint(of row: WindowDestination) -> Color {
        switch row {
        case .page(.home): .wispViolet
        case .page(.tray): .blue
        case .page(.media): .pink
        case .widget(let id): WidgetKind(rawValue: id)?.tint ?? .gray
        case .live(.regionWatch): .teal
        case .live(.downloads): .green
        case .live(.external): .orange
        }
    }
}
