import SwiftUI

@main
struct WispApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var preferences = Preferences.shared

    var body: some Scene {
        // When hidden, opening Wisp again from Finder or Spotlight shows Settings.
        MenuBarExtra(isInserted: $preferences.showMenuBarIcon) {
            Button("Toggle Shelf") { appDelegate.toggleShelf() }
            Button("Clipboard History") { appDelegate.toggleClipboard() }
            Button("Check for Updates…") { appDelegate.services.updater.checkForUpdates() }
                .disabled(!appDelegate.services.updater.canCheckForUpdates)
            Button("Settings…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Wisp") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image("MenuGlyph").accessibilityLabel("Wisp")
        }
    }
}
