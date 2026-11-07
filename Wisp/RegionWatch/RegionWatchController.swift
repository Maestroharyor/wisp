import AppKit
import SwiftUI
import WispCore

/// Watch a window region: pick the region, choose a rule, then watch with a live activity
/// and an alert when the rule fires. Asks for Screen Recording on first use.
@MainActor
final class RegionWatchController {
    private let services: AppServices
    private let watcher = RegionWatcher()
    private let picker = RegionPicker()
    private var setupPanel: ClipboardPanel?
    private var resignObserver: NSObjectProtocol?

    private let setupSize = CGSize(width: 440, height: 170)

    init(services: AppServices) {
        self.services = services
        watcher.battery = { [weak services] in services?.battery.state }
        watcher.onActivity = { [weak services] activity in
            if let activity {
                services?.activities.post(activity, slot: .regionWatch, duration: nil)
            } else {
                services?.activities.remove(.regionWatch)
            }
        }
        watcher.onFired = { [weak services] app, text in
            services?.sounds.play(.alert, fallback: "Tink")
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            services?.activities.post(.notice(symbol: "eye.fill", text: "\(app): \(text)"), slot: .notice, duration: 6)
        }
        watcher.onEnded = { [weak services] reason in
            services?.activities.post(.notice(symbol: "eye.slash.fill", text: reason), slot: .notice, duration: 3)
        }
    }

    var isWatching: Bool { watcher.isWatching }

    // What the watch view shows. Reads go through to the observable watcher, so views follow it.
    var appName: String? { watcher.target?.appName }
    var rule: RegionWatchRule? { watcher.rule }
    var started: Date? { watcher.started }
    var lastChange: Date? { watcher.lastChange }
    var isPaused: Bool { watcher.paused }

    /// The ring action: starts picking, or stops the watch already running.
    func toggle() {
        if isWatching { stop() } else { begin() }
    }

    func stop() {
        watcher.stop()
    }

    /// The pill's stop button: stops and says so, since the pill just disappears otherwise.
    func stopAndConfirm() {
        guard isWatching else { return }
        watcher.stop()
        services.activities.post(
            .notice(symbol: "eye.slash.fill", text: "Stopped watching"), slot: .notice, duration: 2)
    }

    func begin() {
        guard !picker.isPicking else { return }
        closeSetup()
        guard CGPreflightScreenCaptureAccess() else {
            askForScreenRecording()
            return
        }
        services.closeShelves()
        picker.pick { [weak self] rect in
            guard let self, let rect else { return }
            self.picked(rect)
        }
    }

    /// The first time, the system prompt. After that the prompt never shows again, so open
    /// System Settings; a grant there reaches Wisp only after it's reopened.
    private func askForScreenRecording() {
        let askedBefore = Permission.askedScreenRecording
        Permission.screenRecording.request()
        notice(
            askedBefore
                ? "Turn on Screen Recording, then quit and reopen Wisp" : "Allow Screen Recording, then try again")
    }

    private func picked(_ selection: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = RegionGeometry.flipped(selection, primaryHeight: primaryHeight)
        let windows = Self.onScreenWindows()
        guard
            let window = RegionGeometry.topWindow(
                at: CGPoint(x: flipped.midX, y: flipped.midY), in: windows.map(\.candidate),
                excluding: ProcessInfo.processInfo.processIdentifier),
            let region = RegionGeometry.region(flipped, in: window.frame)
        else {
            notice("Drag over a window")
            return
        }
        let appName = windows.first { $0.candidate == window }?.appName ?? "Window"
        let target = RegionTarget(windowID: CGWindowID(window.id), appName: appName, region: region)
        showSetup(for: target, near: selection)
    }

    private func showSetup(for target: RegionTarget, near selection: CGRect) {
        let panel = ClipboardPanel(contentRect: CGRect(origin: .zero, size: setupSize))
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(
            rootView: RegionWatchSetupView(
                appName: target.appName,
                start: { [weak self] rule in
                    self?.closeSetup()
                    self?.watcher.start(target, rule: rule)
                },
                cancel: { [weak self] in self?.closeSetup() }))
        let screen = NSScreen.screens.first { $0.frame.intersects(selection) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? selection
        // Below the selection when there's room, otherwise above it, kept on screen.
        var origin = CGPoint(x: selection.midX - setupSize.width / 2, y: selection.minY - setupSize.height - 12)
        if origin.y < visible.minY { origin.y = selection.maxY + 12 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - setupSize.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - setupSize.height - 8)
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        setupPanel = panel
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            // As in the clipboard panel: pop-up menus take key briefly, so wait before closing.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let panel = self.setupPanel, !panel.isKeyWindow else { return }
                self.closeSetup()
            }
        }
    }

    private func closeSetup() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        setupPanel?.orderOut(nil)
        setupPanel = nil
    }

    private func notice(_ text: String) {
        services.activities.post(.notice(symbol: "eye.fill", text: text), slot: .notice, duration: 3)
    }

    /// On-screen windows front to back, with their owning app's name. Window titles need
    /// Screen Recording and aren't used.
    private static func onScreenWindows() -> [(candidate: WindowCandidate, appName: String)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        // The window server hands back untyped CF dictionaries; each field is checked as it's read.
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                let layer = info[kCGWindowLayer as String] as? Int,
                let pid = info[kCGWindowOwnerPID as String] as? Int32,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { return nil }
            let candidate = WindowCandidate(id: number, layer: layer, frame: bounds, ownerPID: pid)
            return (candidate, info[kCGWindowOwnerName as String] as? String ?? "Window")
        }
    }
}
