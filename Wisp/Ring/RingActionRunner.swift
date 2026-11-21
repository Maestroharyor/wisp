import AppKit
import WispCore

/// Runs a ring action through the services that already do the work.
@MainActor
enum RingActionRunner {
    static func run(_ action: RingAction, files: [URL], services: AppServices) {
        if !files.isEmpty {
            runOnFiles(action, files: files, services: services)
            return
        }
        let quick = services.quickActions
        switch action.kind {
        case .home: services.openShelf(.home)
        case .tray: services.openShelf(.tray)
        case .mediaPage: services.openShelf(.media)
        case .widget:
            if let kind = action.value.flatMap(WidgetKind.init(rawValue:)) { services.openWidget(kind) }
        case .agents: services.openWidget(.agents)
        case .playPause: services.nowPlaying.togglePlayPause()
        case .nextTrack: services.nowPlaying.next()
        case .previousTrack: services.nowPlaying.previous()
        case .clipboard: services.openClipboard()
        case .miniPlayer: services.miniPlayer.toggle()
        case .timer:
            services.timers.setTimer(minutes: action.minutes)
            services.timers.toggleTimer()
        case .keepAwake: quick.toggleKeepAwake()
        case .darkMode: quick.toggleDarkMode()
        case .focus: quick.toggleDoNotDisturb()
        case .screenshot: quick.screenshot()
        case .pickColour: quick.pickColor()
        case .lockScreen: quick.lockScreen()
        case .watchRegion: services.regionWatch.toggle()
        case .captureText: services.textCapture.begin()
        case .ai: services.aiActions.runOnSelection(actionID: action.aiTaskID)
        case .shortcut: if let name = action.value { services.shortcuts.run(name) }
        case .transform: services.openTransform([])
        case .dropAction, .airDrop, .zip:
            services.activities.post(
                .notice(symbol: action.symbol, text: "Drag files onto the orb, then onto \(action.title)"),
                slot: .notice, duration: 2)
        case .form: services.cycleForm()
        case .quickInput: services.openQuickInput()
        case .app: openApp(action, services: services)
        case .link:
            if let url = action.value.flatMap(RingLinks.normalised) {
                NSWorkspace.shared.open(url)
            } else {
                notice("link.badge.plus", "That link can't be opened", services: services)
            }
        case .folder:
            withFolder(action, services: services) { NSWorkspace.shared.open($0) }
        case .none: break
        }
    }

    /// Brings a running app forward (as clicking it in the Dock does), or else opens it.
    private static func openApp(_ action: RingAction, services: AppServices) {
        guard let id = action.value, !id.isEmpty else { return }
        // Opening a running app is what the Dock does: it comes forward, unhidden, with a window.
        // Activating it directly can be refused while Wisp isn't the active app.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            notice("questionmark.app", "\(action.title) isn't installed", services: services)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Runs `body` with a folder segment's folder once it's known to be there. The check runs on
    /// a dispatch queue, since a folder on a share that has gone away can block for a long time.
    private static func withFolder(
        _ action: RingAction, services: AppServices, _ body: @escaping @MainActor (URL) -> Void
    ) {
        guard let path = action.value, !path.isEmpty else { return }
        let title = action.title
        Task { @MainActor in
            let exists = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var isFolder: ObjCBool = false
                    let found = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
                    continuation.resume(returning: found && isFolder.boolValue)
                }
            }
            if exists {
                body(URL(fileURLWithPath: path, isDirectory: true))
            } else {
                notice("questionmark.folder", "\(title) isn't there any more", services: services)
            }
        }
    }

    private static func notice(_ symbol: String, _ text: String, services: AppServices) {
        services.activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: 2)
    }

    /// Copies files into a folder segment off the main thread, keeping both when a name is
    /// taken, as Finder does.
    private static func copy(_ files: [URL], into folder: URL, services: AppServices) {
        Task {
            let copied = await copyFiles(files, into: folder)
            let name = folder.lastPathComponent
            if copied == files.count {
                notice(
                    "folder.badge.plus", copied == 1 ? "Copied to \(name)" : "Copied \(copied) to \(name)",
                    services: services)
            } else {
                notice("exclamationmark.triangle", "Copied \(copied) of \(files.count) to \(name)", services: services)
            }
        }
    }

    private nonisolated static func copyFiles(_ files: [URL], into folder: URL) async -> Int {
        await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let existing = Set((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
            let names = FolderDrop.names(for: files.map(\.lastPathComponent), existing: existing)
            var copied = 0
            for (file, name) in zip(files, names) {
                do {
                    try manager.copyItem(at: file, to: folder.appendingPathComponent(name))
                    copied += 1
                } catch {
                    continue
                }
            }
            return copied
        }.value
    }

    private static func runOnFiles(_ action: RingAction, files: [URL], services: AppServices) {
        switch action.kind {
        case .tray: services.tray.add(files)
        case .airDrop: services.tray.airDrop(files)
        case .zip: services.tray.zip(files)
        case .transform: services.openTransform(files)
        case .dropAction:
            let id = action.value.flatMap(UUID.init(uuidString:))
            if let drop = services.preferences.dropActions.first(where: { $0.id == id }) {
                services.dropActions.run(drop, on: files)
            } else {
                notice("questionmark", "That drop action was removed", services: services)
            }
        case .app:
            guard let id = action.value, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                notice("questionmark.app", "\(action.title) isn't installed", services: services)
                return
            }
            NSWorkspace.shared.open(files, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        case .folder:
            withFolder(action, services: services) { copy(files, into: $0, services: services) }
        default: break
        }
    }
}
