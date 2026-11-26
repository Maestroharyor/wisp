import EventKit
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
    /// The window Home's card picker is showing.
    var customisingHome = false
    /// The ⌘K bar that finds and creates things is open.
    var showsCommandBar = false {
        didSet { if !showsCommandBar { commandQuery = "" } }
    }
    /// What's typed in the command bar; cleared when it closes.
    var commandQuery = ""

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
        case .commandBar: showsCommandBar.toggle()
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
            // The switcher has no window row of its own; the Agents page lists the same sessions.
            self = detail.live.map(WindowDestination.live) ?? .widget(WidgetKind.agents.rawValue)
        }
    }
}

extension ActivityDetail {
    var live: WindowLive? {
        switch self {
        case .regionWatch: .regionWatch
        case .downloads: .downloads
        case .external: .external
        case .sessionSwitcher: nil
        }
    }
}

/// The shelf window: a sidebar panel floating inside it, a top bar, and the chosen row's page
/// filling the rest. Follows the system's Light or Dark mode.
/// The root reads only what picks the selection (preferences and whether each live activity
/// runs); rows, titles and pages are in their own views.
struct ShelfWindowView: View {
    let model: NotchModel
    @Bindable var navigation: WindowNavigation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    var body: some View {
        let selection = navigation.selection(in: navigation.sections(services: model.services))
        let showsSidebar = navigation.columns != .detailOnly
        ZStack(alignment: .top) {
            WindowBackdrop()
            HStack(spacing: WindowShell.inset) {
                if showsSidebar {
                    WindowSidebarPanel(model: model, navigation: navigation, selection: selection)
                        .frame(
                            width: width < WindowShell.compactBelow
                                ? WindowShell.compactSidebarWidth : WindowShell.sidebarWidth
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 10) {
                    WindowTopBar(model: model, navigation: navigation, selection: selection)
                    WindowDetail(model: model, navigation: navigation, selection: selection)
                        .clipShape(RoundedRectangle(cornerRadius: WindowShell.panelRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: WindowShell.panelRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                .allowsHitTesting(false))
                    WindowPrivacyLine()
                }
            }
            .padding(WindowShell.inset)
            if navigation.showsCommandBar {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { navigation.showsCommandBar = false }
                    .transition(.opacity)
                CommandBar(model: model, navigation: navigation)
                    .padding(.top, WindowShell.inset + WindowShell.barHeight + 24)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .wispAnimation(.wispSmooth, value: showsSidebar)
        .wispAnimation(.wispControl, value: navigation.showsCommandBar)
        .tint(Color.wispViolet)
        .environment(\.valueFont, model.preferences.appearance.valueFont)
        .environment(\.contextThresholds, model.preferences.contextThresholds)
        .wispBaseFont()
        .environment(\.wispTextScale, model.preferences.textScale.factor)
        .sheet(isPresented: $navigation.customisingHome) {
            HomeCardsSheet(preferences: model.preferences)
        }
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

/// The line under the page saying where everything is kept.
private struct WindowPrivacyLine: View {
    var body: some View {
        Label("All of this stays on this Mac.", systemImage: "lock.fill")
            .wispFont(.caption)
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity)
            .padding(.bottom, -2)
    }
}

/// The selected row's page, with its title and toolbar.
private struct WindowDetail: View {
    let model: NotchModel
    let navigation: WindowNavigation
    let selection: WindowDestination

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The row shown before the current one, to tell whether the swap fades.
    @State private var previous: WindowDestination?

    private var services: AppServices { model.services }

    var body: some View {
        detail(selection)
            .onChange(of: selection, initial: true) { _, row in previous = row }
    }

    /// Widget pages swap instantly, as their controls differ; a fade would show both for a moment.
    private var fades: Bool {
        guard !reduceMotion else { return false }
        if case .widget = selection { return false }
        if case .widget = previous { return false }
        return true
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
        // Swaps right away, like Notes or Music; a short fade between the Wisp pages and live
        // rows unless Reduce Motion is on.
        .animation(fades ? .easeOut(duration: 0.12) : nil, value: selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let hub = services.agents
            ZStack {
                if let approval = hub.approvals.first {
                    ApprovalBar(approval: approval, hub: hub, model: model)
                        .id(approval.id)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .wispTransition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .wispAnimation(.wispSmooth, value: hub.approvals.first?.id)
        }
        .background(WindowCanvas())
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
                WindowWidgetDetail(kind: kind, model: model)
            }
        case .live(let live):
            WindowPageFrame {
                WindowPageHeader(
                    symbol: WindowRow.symbol(of: destination, services: services),
                    tint: WindowRow.tint(of: destination),
                    title: WindowRow.title(of: destination, services: services), subtitle: liveSubtitle(live))
            } content: {
                Group {
                    switch live {
                    case .regionWatch: RegionWatchDetail(watch: services.regionWatch)
                    case .downloads: DownloadsDetail(monitor: services.downloads)
                    case .external: ExternalActivityDetail(automation: services.automation)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .windowCardBackground()
            }
        }
    }

    private func liveSubtitle(_ live: WindowLive) -> String {
        switch live {
        case .regionWatch: "A part of a window, watched for changes while you do something else"
        case .downloads: "Files downloading now, with how far along each one is"
        case .external: "An activity another app or script sent to Wisp"
        }
    }
}

/// How each sidebar row is labelled.
@MainActor
enum WindowRow {
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

/// Behind the panels: a light grey in Light mode so white cards and glass stand off it, and a
/// deep near-black with a faint violet light from the top in Dark mode.
private struct WindowBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            ZStack {
                Color(red: 0.055, green: 0.05, blue: 0.075)
                RadialGradient(
                    colors: [Color.wispViolet.opacity(0.12), .clear], center: .top, startRadius: 0, endRadius: 700)
            }
            .ignoresSafeArea()
        } else {
            Color(white: 0.93).ignoresSafeArea()
        }
    }
}

/// The page area behind the cards: a step lighter than the window behind the panels, so the
/// page reads as a panel of its own.
private struct WindowCanvas: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            Color.white.opacity(0.025)
        } else {
            Color(white: 0.965)
        }
    }
}
