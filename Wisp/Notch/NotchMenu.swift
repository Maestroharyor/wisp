import AppKit
import WispCore

/// Right-click menu on the notch or shelf: Open, Tools, Profile and Form, then Settings, Check for Updates
/// and Quit.
@MainActor
enum NotchMenu {
    static func show(
        at location: CGPoint, customiseHome: @escaping @MainActor () -> Void,
        openPage: @escaping @MainActor (ShelfPage) -> Void, form: FormFactor, forms: [FormFactor],
        setForm: @escaping @MainActor (FormFactor) -> Void, openAsWindow: @escaping @MainActor () -> Void,
        moveBack: MoveBack?, services: AppServices
    ) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(pagesItem(openPage))
        menu.addItem(toolsItem(customiseHome: customiseHome, services: services))
        menu.addItem(profilesItem(services: services))
        menu.addItem(
            formItem(current: form, forms: forms, setForm: setForm, openAsWindow: openAsWindow, moveBack: moveBack))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", symbol: "gearshape", action: services.openSettings))
        let updates = item("Check for Updates…", symbol: "arrow.down.circle", action: services.updater.checkForUpdates)
        // Off while a check is already running, as Sparkle reports.
        updates.isEnabled = services.updater.canCheckForUpdates
        menu.addItem(updates)
        menu.addItem(item("Quit Wisp", symbol: "power") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: location, in: nil)
    }

    /// Puts a dragged island back where its placement puts it.
    struct MoveBack {
        let title: String
        let action: @MainActor () -> Void

        /// `spot` is the placement's title, such as "Top right".
        init(spot: String, action: @escaping @MainActor () -> Void) {
            title = "Move back to the \(spot.lowercased())"
            self.action = action
        }
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

    /// The panels and windows Wisp opens, and Customise Home.
    private static func toolsItem(customiseHome: @escaping @MainActor () -> Void, services: AppServices) -> NSMenuItem {
        let parent = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(item("Clipboard History", symbol: "doc.on.clipboard", action: services.openClipboard))
        submenu.addItem(item("Transform Files…", symbol: "wand.and.stars") { services.openTransform([]) })
        submenu.addItem(item("Mini Player", symbol: "pip") { services.miniPlayer.toggle() })
        if services.regionWatch.isWatching {
            submenu.addItem(item("Stop Watching Region", symbol: "eye.slash") { services.regionWatch.stop() })
        } else {
            submenu.addItem(item("Watch a Window Region…", symbol: "eye") { services.regionWatch.begin() })
        }
        submenu.addItem(item("Customise Home", symbol: "square.grid.2x2", action: customiseHome))
        parent.submenu = submenu
        return parent
    }

    /// Every form, the current one ticked, then the one-off window and, for a moved island,
    /// the way back to its spot.
    private static func formItem(
        current: FormFactor, forms: [FormFactor], setForm: @escaping @MainActor (FormFactor) -> Void,
        openAsWindow: @escaping @MainActor () -> Void, moveBack: MoveBack?
    ) -> NSMenuItem {
        let parent = NSMenuItem(title: "Form", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: current.symbol, accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for form in forms {
            let entry = item(form.title, symbol: form.symbol) { setForm(form) }
            entry.state = form == current ? .on : .off
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Open as Window", symbol: "macwindow.on.rectangle", action: openAsWindow))
        if let moveBack {
            submenu.addItem(item(moveBack.title, symbol: "arrow.uturn.backward", action: moveBack.action))
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
