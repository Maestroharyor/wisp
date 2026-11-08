import Foundation

/// A Wisp page in the shelf window's sidebar.
public enum WindowPage: String, CaseIterable, Sendable {
    case home
    case tray
    case media
}

/// A live activity with a view of its own, listed in the sidebar while it runs.
public enum WindowLive: String, CaseIterable, Sendable {
    case regionWatch
    case downloads
    case external
}

/// A row in the shelf window's sidebar: a Wisp page, a widget (by its id) or a live activity.
public enum WindowDestination: Hashable, Sendable {
    case page(WindowPage)
    case widget(String)
    case live(WindowLive)

    public static let home = WindowDestination.page(.home)

    /// "page:home", "widget:calendar", "live:downloads", for saving the last selection.
    public var rawValue: String {
        switch self {
        case .page(let page): "page:\(page.rawValue)"
        case .widget(let id): "widget:\(id)"
        case .live(let live): "live:\(live.rawValue)"
        }
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "page":
            guard let page = WindowPage(rawValue: parts[1]) else { return nil }
            self = .page(page)
        case "widget":
            self = .widget(parts[1])
        case "live":
            guard let live = WindowLive(rawValue: parts[1]) else { return nil }
            self = .live(live)
        default:
            return nil
        }
    }

}

/// A group of sidebar rows.
public struct WindowSidebarSection: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case wisp
        case widgets
        case live
    }

    public let kind: Kind
    public let rows: [WindowDestination]

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .wisp: "Wisp"
        case .widgets: "Widgets"
        case .live: "Live"
        }
    }
}

/// What the shelf window's sidebar lists, and where requests from the shell land in it.
public enum WindowSidebar {
    /// Wisp's pages, then the enabled widgets in the Widgets grid's order, then the live
    /// activities that are running. Empty sections are left out. `visiting` is a widget
    /// that isn't enabled but was opened anyway (a timer pill, say), listed after the others
    /// while it's selected.
    public static func sections(
        enabledWidgets: [String], gridOrder: [String], live: [WindowLive], visiting: String? = nil
    ) -> [WindowSidebarSection] {
        var sections = [WindowSidebarSection(kind: .wisp, rows: WindowPage.allCases.map(WindowDestination.page))]
        var widgets = WidgetGrid.merge(order: gridOrder, enabled: enabledWidgets)
        if let visiting, !widgets.contains(visiting) { widgets.append(visiting) }
        if !widgets.isEmpty {
            sections.append(WindowSidebarSection(kind: .widgets, rows: widgets.map(WindowDestination.widget)))
        }
        let running = WindowLive.allCases.filter(live.contains)
        if !running.isEmpty {
            sections.append(WindowSidebarSection(kind: .live, rows: running.map(WindowDestination.live)))
        }
        return sections
    }

    /// The selection while its row is listed; Home once its widget is switched off or its
    /// activity ends.
    public static func resolve(_ selection: WindowDestination?, in sections: [WindowSidebarSection])
        -> WindowDestination
    {
        guard let selection, sections.contains(where: { $0.rows.contains(selection) }) else { return .home }
        return selection
    }

    /// The row for a shelf page by name. The Widgets page has no row of its own, so it opens
    /// its first widget, or Home when none is on.
    public static func destination(forPage name: String, gridWidgets: [String]) -> WindowDestination {
        if name == "widgets" { return gridWidgets.first.map(WindowDestination.widget) ?? .home }
        return WindowPage(rawValue: name).map(WindowDestination.page) ?? .home
    }
}

/// The shelf window's own keys: ⌘1 to ⌘3 pick Home, Tray and Media, ⌘0 shows or hides the
/// sidebar.
public enum WindowKeys {
    public enum Action: Equatable, Sendable {
        case select(WindowPage)
        case toggleSidebar
    }

    /// `key` is the character typed without modifiers; `commandOnly` is whether ⌘ is the only
    /// modifier held.
    public static func action(key: String, commandOnly: Bool) -> Action? {
        guard commandOnly else { return nil }
        switch key {
        case "1": return .select(.home)
        case "2": return .select(.tray)
        case "3": return .select(.media)
        case "0": return .toggleSidebar
        default: return nil
        }
    }
}
