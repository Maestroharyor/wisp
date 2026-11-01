import AppKit

/// Right-click menu on the notch or shelf.
@MainActor
enum NotchMenu {
    static func show(
        at location: CGPoint, customiseHome: @escaping @MainActor () -> Void,
        openPage: @escaping @MainActor (ShelfPage) -> Void, services: AppServices
    ) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(pagesItem(openPage))
        menu.addItem(item("Customise Home", symbol: "square.grid.2x2", action: customiseHome))
        menu.addItem(item("Clipboard History", symbol: "doc.on.clipboard", action: services.openClipboard))
        menu.addItem(item("Transform Files…", symbol: "wand.and.stars") { services.openTransform([]) })
        menu.addItem(item("Mini Player", symbol: "pip") { services.miniPlayer.toggle() })
        menu.addItem(profilesItem(services: services))
        menu.addItem(.separator())
        let update = item("Check for Updates…", symbol: "arrow.down.circle") { services.updater.checkForUpdates() }
        update.isEnabled = services.updater.canCheckForUpdates
        menu.addItem(update)
        menu.addItem(item("Settings…", symbol: "gearshape", action: services.openSettings))
        menu.addItem(item("Quit Wisp", symbol: "power") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: location, in: nil)
    }

    /// The shelf's pages, which matters most when the page switcher is hidden.
    private static func pagesItem(_ openPage: @escaping @MainActor (ShelfPage) -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: nil)
        let submenu = NSMenu()
        let pages: [(ShelfPage, String, String)] = [
            (.home, "Home", "house"), (.tray, "Tray", "tray"), (.media, "Media", "music.note"),
            (.widgets, "Widgets", "square.grid.2x2"),
        ]
        for (page, title, symbol) in pages {
            submenu.addItem(item(title, symbol: symbol) { openPage(page) })
        }
        parent.submenu = submenu
        return parent
    }

    private static func profilesItem(services: AppServices) -> NSMenuItem {
        let parent = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil)
        let submenu = NSMenu()
        let preferences = services.preferences
        for (index, profile) in preferences.profiles.enumerated() {
            let entry = item(profile.name, symbol: "rectangle.stack") { services.context.choose(profile) }
            entry.image = nil
            entry.state = profile.name == preferences.activeProfile ? .on : .off
            if index < 9 { entry.toolTip = "Hyper+\(index + 1)" }
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private static func item(_ title: String, symbol: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        item.target = target
        // NSMenuItem holds its target weakly; keep the closure box alive with the item.
        item.representedObject = target
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}

/// Bridges a Swift closure to a target/action pair.
@MainActor
final class MenuAction: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() { action() }
}
