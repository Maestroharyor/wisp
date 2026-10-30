import AppKit
import Observation
import Sparkle

/// Sparkle's standard updater: a daily check of the appcast on GitHub Releases, its
/// update window, the download, the signature check and the relaunch. Wisp only adds
/// the menu items and the About pane controls.
@MainActor
@Observable
final class Updater {
    private(set) var canCheckForUpdates = false
    private(set) var lastCheck: Date?

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
        ]
    }

    var automaticallyChecks: Bool {
        get { access(keyPath: \.automaticallyChecks); return controller.updater.automaticallyChecksForUpdates }
        set {
            withMutation(keyPath: \.automaticallyChecks) { controller.updater.automaticallyChecksForUpdates = newValue }
        }
    }

    var automaticallyDownloads: Bool {
        get { access(keyPath: \.automaticallyDownloads); return controller.updater.automaticallyDownloadsUpdates }
        set {
            withMutation(keyPath: \.automaticallyDownloads) {
                controller.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    /// Wisp has no Dock icon, so bring it forward or Sparkle's window opens behind others.
    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    private func refresh() {
        canCheckForUpdates = controller.updater.canCheckForUpdates
        lastCheck = controller.updater.lastUpdateCheckDate
    }
}
