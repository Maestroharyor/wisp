import AppKit
import SwiftUI

/// The icon of the app an agent session runs in (Ghostty, Warp, VS Code...). Draws nothing
/// when the app is unknown, so rows without one keep their old spacing.
struct TerminalIcon: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let app = bundleID.flatMap(TerminalApps.app(for:)) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .help(app.name)
                .accessibilityLabel(app.name)
        }
    }
}

/// App icons and names by bundle ID. The pill redraws every second while it counts, so the
/// lookup is done once per app.
@MainActor
enum TerminalApps {
    struct App {
        let name: String
        let icon: NSImage
    }

    /// Only apps that were found: a miss is looked up again, so an app installed while Wisp
    /// runs gets its icon.
    private static var cache: [String: App] = [:]

    static func app(for bundleID: String) -> App? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        // The name keeps ".app" when Finder shows extensions.
        let name = FileManager.default.displayName(atPath: url.path)
        let app = App(
            name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            icon: NSWorkspace.shared.icon(forFile: url.path))
        cache[bundleID] = app
        return app
    }

    static func name(for bundleID: String?) -> String? { bundleID.flatMap(app(for:))?.name }
}
