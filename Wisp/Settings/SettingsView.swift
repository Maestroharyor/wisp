import AppKit
import SwiftUI
import WispCore

/// Opens Settings in a normal window. Wisp is a menu bar app, so SwiftUI's Settings
/// scene does not come forward reliably; this does.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let services: AppServices
    private let hotkeys: HotkeyCenter

    init(services: AppServices, hotkeys: HotkeyCenter) {
        self.services = services
        self.hotkeys = hotkeys
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(services: services, hotkeys: hotkeys))
        let window = NSWindow(contentViewController: host)
        window.title = "Wisp Settings"
        // The sidebar runs to the top edge, as in System Settings.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 820, height: 600))
        window.contentMinSize = CGSize(width: 700, height: 480)
        window.setFrameAutosaveName("WispSettings")
        return window
    }
}

/// Sidebar of panes (searchable, grouped, with a badge for missing permissions) and the
/// selected pane beside it.
struct SettingsView: View {
    let services: AppServices
    let hotkeys: HotkeyCenter
    @State private var model: SettingsModel

    init(services: AppServices, hotkeys: HotkeyCenter) {
        self.services = services
        self.hotkeys = hotkeys
        _model = State(initialValue: SettingsModel(preferences: services.preferences))
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(SettingsSection.allCases) { section in
                    let panes = section.panes.filter(model.visiblePanes.contains)
                    if !panes.isEmpty {
                        Section(section.title) {
                            ForEach(panes) { pane in
                                Label {
                                    Text(pane.title)
                                } icon: {
                                    IconTile(symbol: pane.symbol, tint: pane.tint)
                                }
                                .badge(pane == .permissions ? model.missing.count : 0)
                                .tag(pane)
                            }
                        }
                    }
                }
            }
            .searchable(text: $model.query, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 700, minHeight: 480)
        .task {
            // Grants happen in System Settings; keep the health badge current while open.
            while !Task.isCancelled {
                model.refreshHealth()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let pane = model.selection {
            VStack(spacing: 0) {
                PaneHeader(pane: pane)
                paneView(pane)
            }
            .id(pane)
        } else {
            ContentUnavailableView.search(text: model.query)
        }
    }

    @ViewBuilder private func paneView(_ pane: SettingsPaneID) -> some View {
        let preferences = services.preferences
        switch pane {
        case .general:
            GeneralSettings(
                preferences: preferences, hotkeys: hotkeys, accent: services.accent, glow: services.glow,
                missing: model.missing
            ) {
                model.selection = .permissions
            }
        case .notch:
            NotchSettings(
                preferences: preferences, accent: services.accent, glow: services.glow, shortcuts: services.shortcuts)
        case .appearance: AppearanceSettings(preferences: preferences, services: services)
        case .activities: ActivitySettings(preferences: preferences)
        case .widgets: WidgetSettings(preferences: preferences, shortcuts: services.shortcuts)
        case .profiles: ProfileSettings(preferences: preferences, context: services.context)
        case .clipboard: ClipboardSettings(preferences: preferences, store: services.clipboard)
        case .notifications: NotificationSettings(preferences: preferences, monitor: services.notifications)
        case .agents: AgentSettings(hub: services.agents, preferences: preferences)
        case .permissions: PermissionSettings(onChange: model.refreshHealth)
        case .about: AboutSettings(preferences: preferences, updater: services.updater, runSetup: services.openSetup)
        }
    }
}
