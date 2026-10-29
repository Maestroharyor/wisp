import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences.shared
    let services: AppServices
    let hotkeys: HotkeyCenter
    private let coordinator: NotchCoordinator
    private let settings: SettingsWindowController
    private let clipboardPanel: ClipboardPanelController
    private var terminationSignal: DispatchSourceSignal?

    override init() {
        services = AppServices(preferences: Preferences.shared)
        hotkeys = HotkeyCenter(preferences: Preferences.shared)
        coordinator = NotchCoordinator(services: services)
        settings = SettingsWindowController(services: services, hotkeys: hotkeys)
        clipboardPanel = ClipboardPanelController(services: services)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        services.openSettings = { [weak self] in self?.showSettings() }
        services.openClipboard = { [weak self] in self?.toggleClipboard() }
        services.start()
        coordinator.start()
        hotkeys.onToggle = { [weak self] in self?.toggleShelf() }
        hotkeys.onClipboard = { [weak self] in self?.toggleClipboard() }
        hotkeys.start()
        handleTerminationSignal()
    }

    /// Launching Wisp again while it runs (Finder, Spotlight, `open`) shows Settings,
    /// so Settings stays reachable even when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
        // Caps Lock must work again after Wisp quits.
        hotkeys.shutdown()
    }

    func toggleShelf() {
        coordinator.toggleShelf()
    }

    func toggleClipboard() {
        clipboardPanel.toggle()
    }

    func showSettings() {
        settings.show()
    }

    /// `kill`/`pkill` send SIGTERM, which skips applicationWillTerminate. Route it
    /// through a normal quit so the Caps Lock remap is always undone.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }
}
