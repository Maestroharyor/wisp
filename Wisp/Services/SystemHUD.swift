import AppKit
import WispCore

/// Replaces the system volume, brightness and Caps Lock overlays with notch activities.
@MainActor
final class SystemHUD {
    private let preferences: Preferences
    private let activities: ActivityCenter
    private let tap = MediaKeyTap()
    private var flagMonitors: [Any] = []
    private var capsLockOn = NSEvent.modifierFlags.contains(.capsLock)
    private var accessWaiter: Task<Void, Never>?
    private var volumeObserver: VolumeObserver?
    private var brightnessTask: Task<Void, Never>?
    private var lastBrightness: Double?
    /// Changes made by Wisp's own key handling already posted an activity.
    private var lastHandledKey = Date.distantPast

    /// How long a level overlay stays after the last key press.
    private let levelDuration: TimeInterval = 1.6

    init(preferences: Preferences, activities: ActivityCenter) {
        self.preferences = preferences
        self.activities = activities
    }

    func start() {
        tap.handler = { [weak self] event, fine in self?.handle(event, fine: fine) ?? false }
        startTapWhenTrusted()

        let handler: (NSEvent) -> Void = { [weak self] event in
            let on = event.modifierFlags.contains(.capsLock)
            MainActor.assumeIsolated { self?.capsLockChanged(on) }
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
        flagMonitors = [global, local].compactMap { $0 }

        // Without Accessibility the keys can't be intercepted, so watch the values
        // instead: the notch still reacts (alongside the macOS overlay).
        volumeObserver = SystemVolume.observe { [weak self] in self?.volumeChangedExternally() }
        brightnessTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkBrightness()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func stop() {
        volumeObserver?.stop()
        brightnessTask?.cancel()
        accessWaiter?.cancel()
        tap.stop()
        flagMonitors.forEach(NSEvent.removeMonitor)
        flagMonitors = []
    }

    private func startTapWhenTrusted() {
        guard AccessibilityPermission.isTrusted else {
            accessWaiter = Task { [weak self] in
                await AccessibilityPermission.waitUntilTrusted()
                guard !Task.isCancelled else { return }
                self?.tap.start()
            }
            return
        }
        tap.start()
    }

    private func volumeChangedExternally() {
        guard preferences.volumeHUD, Date.now.timeIntervalSince(lastHandledKey) > 0.4 else { return }
        let muted = SystemVolume.isMuted
        activities.post(
            .level(.volume, value: muted ? 0 : SystemVolume.volume ?? 0, muted: muted), slot: .level,
            duration: levelDuration)
    }

    private func checkBrightness() {
        guard preferences.brightnessHUD, let value = DisplayBrightness.brightness else { return }
        defer { lastBrightness = value }
        guard let lastBrightness, abs(value - lastBrightness) > 0.004,
            Date.now.timeIntervalSince(lastHandledKey) > 0.4
        else { return }
        activities.post(.level(.brightness, value: value, muted: false), slot: .level, duration: levelDuration)
    }

    /// Returns true when Wisp handled the key, so the system overlay is suppressed.
    private func handle(_ event: MediaKeyEvent, fine: Bool) -> Bool {
        lastHandledKey = .now
        switch event.key {
        case .volumeUp, .volumeDown, .mute:
            guard preferences.volumeHUD, SystemVolume.canSetVolume else { return false }
            if event.isDown { changeVolume(event.key, fine: fine) }
            return true
        case .brightnessUp, .brightnessDown:
            guard preferences.brightnessHUD, DisplayBrightness.isAvailable, pointerOnBuiltInDisplay else {
                return false
            }
            if event.isDown { changeBrightness(up: event.key == .brightnessUp, fine: fine) }
            return true
        }
    }

    private func changeVolume(_ key: MediaKey, fine: Bool) {
        let current = SystemVolume.volume ?? 0
        if key == .mute {
            SystemVolume.setMuted(!SystemVolume.isMuted)
        } else {
            let next = LevelStep.next(from: SystemVolume.isMuted ? 0 : current, up: key == .volumeUp, fine: fine)
            SystemVolume.setVolume(next)
            if next == 0 { SystemVolume.setMuted(true) }
        }
        let muted = SystemVolume.isMuted
        activities.post(
            .level(.volume, value: muted ? 0 : SystemVolume.volume ?? 0, muted: muted),
            slot: .level,
            duration: levelDuration
        )
    }

    private func changeBrightness(up: Bool, fine: Bool) {
        let next = LevelStep.next(from: DisplayBrightness.brightness ?? 0.5, up: up, fine: fine)
        DisplayBrightness.setBrightness(next)
        activities.post(.level(.brightness, value: next, muted: false), slot: .level, duration: levelDuration)
    }

    private var pointerOnBuiltInDisplay: Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return true }
        return screen.isBuiltIn
    }

    private func capsLockChanged(_ on: Bool) {
        guard on != capsLockOn else { return }
        capsLockOn = on
        guard preferences.capsLockHUD else { return }
        activities.post(.capsLock(on: on), slot: .capsLock, duration: 1.4)
    }
}
