import SwiftUI

@main
struct WispApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Toggle Shelf") { appDelegate.toggleShelf() }
            Button("Clipboard History") { appDelegate.toggleClipboard() }
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
