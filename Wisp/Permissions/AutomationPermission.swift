import AppKit
import CoreServices
import WispCore

/// Automation (Apple Events) is granted per app Wisp controls, and System Settings lists Wisp
/// only after macOS has asked about one of them. Allow asks now, for the apps Wisp scripts.
@MainActor
enum AutomationPermission {
    /// Always asked about: Finder (Empty Trash) and System Events (Dark Mode). Both are part of macOS.
    private static let systemTargets = ["com.apple.finder", "com.apple.systemevents"]
    /// Asked about only while open, so Allow never launches them: Music and Spotify
    /// (playback), Messages (replies).
    private static let appTargets = ["com.apple.Music", "com.spotify.client", "com.apple.MobileSMS"]

    private static let systemEventsURL = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")

    /// Shows macOS's prompt for each target that hasn't been asked about, which adds Wisp to the
    /// Automation list, then opens that list.
    static func request() {
        Task {
            // macOS can only ask about a running app; System Events quits itself when idle.
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemevents").isEmpty {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: systemEventsURL, configuration: configuration)
            }
            let running = appTargets.filter {
                !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
            }
            // Asking blocks until the person answers, so it runs off the main thread.
            let targets = systemTargets + running
            await Task.detached { for target in targets { _ = ask(target) } }.value
            await refresh()
            // Once allowed there's nothing left to do in System Settings; open it only to
            // switch a denied app back on.
            if status != true { Permission.automation.openSettings() }
        }
    }

    /// Granted, not granted, or nil when none of the always-asked apps can answer, as of the
    /// last `refresh()`.
    private(set) static var status: Bool?

    /// Asking macOS takes tens of milliseconds per app, so it runs off the main thread. Never prompts.
    static func refresh() async {
        let targets = systemTargets
        status = await Task.detached {
            AutomationStatus.summary(targets.map { determine($0, askUserIfNeeded: false) })
        }.value
    }

    /// `noErr` once allowed; macOS shows its prompt first if it hasn't asked about `bundleID`.
    private nonisolated static func ask(_ bundleID: String) -> OSStatus {
        determine(bundleID, askUserIfNeeded: true)
    }

    private nonisolated static func determine(_ bundleID: String, askUserIfNeeded: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { AECreateDesc(typeApplicationBundleID, $0, strlen($0), &target) }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, askUserIfNeeded)
    }
}
