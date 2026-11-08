import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import Observation
import WispCore

/// One-tap system actions for the Quick Toggles widget.
@MainActor
@Observable
final class QuickActions {
    private(set) var keepAwake = false
    /// When the current Keep awake ends on its own; nil while off or kept on indefinitely.
    private(set) var keepAwakeSession: KeepAwakeSession?
    private(set) var darkMode = QuickActions.systemIsDark
    private(set) var desktopHidden = QuickActions.finderHidesDesktop

    /// Posts a short notice pill.
    var onNotice: (String, String) -> Void = { _, _ in }
    /// Closes open shelves before an action that needs the screen.
    var closeShelves: () -> Void = {}
    /// Takes the shelf window off screen for a capture; the returned closure brings it back.
    var stepAsideWindow: () -> @MainActor @Sendable () -> Void = { {} }

    @ObservationIgnored private let awake = SleepAssertion(
        type: kIOPMAssertionTypePreventUserIdleDisplaySleep, name: "Wisp Keep Awake")
    /// Ends a timed Keep awake when its time is up.
    @ObservationIgnored private var keepAwakeExpiry: Task<Void, Never>?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let shortcuts: ShortcutsRunner

    init(preferences: Preferences, shortcuts: ShortcutsRunner) {
        self.preferences = preferences
        self.shortcuts = shortcuts
    }

    func refresh() {
        darkMode = Self.systemIsDark
        desktopHidden = Self.finderHidesDesktop
    }

    // MARK: Keep Awake

    func toggleKeepAwake() {
        if keepAwake {
            endKeepAwake()
        } else {
            startKeepAwake(KeepAwakeSession.lasting(nil, from: .now))
        }
    }

    /// Keeps the Mac awake for `session`, replacing one already running.
    func startKeepAwake(_ session: KeepAwakeSession) {
        keepAwakeExpiry?.cancel()
        keepAwakeExpiry = nil
        // The assertion is held once; a new length only moves the end.
        if !keepAwake { keepAwake = awake.hold() }
        guard keepAwake else { return onNotice("exclamationmark.triangle.fill", "Couldn't keep the Mac awake") }
        keepAwakeSession = session.ends == nil ? nil : session
        if session.ends != nil {
            keepAwakeExpiry = Task { [weak self] in
                // Checked again after waking, in case the clock changed while it slept.
                while !Task.isCancelled, !session.isExpired(now: .now) {
                    try? await Task.sleep(for: .seconds(min(session.remaining(now: .now) ?? 60, 60)))
                }
                guard !Task.isCancelled else { return }
                self?.endKeepAwake()
            }
        }
        let until = session.ends.map { "Awake until \($0.formatted(date: .omitted, time: .shortened))" }
        onNotice("cup.and.saucer.fill", until ?? "Staying awake")
    }

    func endKeepAwake() {
        keepAwakeExpiry?.cancel()
        keepAwakeExpiry = nil
        keepAwakeSession = nil
        guard keepAwake else { return }
        awake.release()
        keepAwake = false
        onNotice("moon.zzz.fill", "Sleep allowed")
    }

    // MARK: Appearance

    func toggleDarkMode() {
        let script = """
            tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
            """
        Task {
            let ok = await Self.runAppleScript(script)
            refresh()
            if !ok { onNotice("exclamationmark.triangle.fill", "Allow Wisp to control System Events") }
        }
    }

    func toggleDesktopIcons() {
        let hide = !desktopHidden
        guard
            confirm(
                hide ? "Hide desktop icons?" : "Show desktop icons?",
                detail: "Finder restarts to apply this. Open Finder windows reopen.",
                action: hide ? "Hide" : "Show")
        else { return }
        Task {
            _ = try? await ProcessRunner.run(
                "/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"])
            _ = try? await ProcessRunner.run("/usr/bin/killall", ["Finder"])
            refresh()
        }
    }

    // MARK: Capture

    func screenshot() {
        closeShelves()
        let restore = stepAsideWindow()
        Task {
            defer { restore() }
            // Let the shelf animate away first.
            try? await Task.sleep(for: .milliseconds(350))
            // A cancelled capture leaves the pasteboard alone, which may already hold an image.
            let before = NSPasteboard.general.changeCount
            _ = try? await ProcessRunner.run("/usr/sbin/screencapture", ["-i", "-c"])
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount != before,
                pasteboard.types?.contains(.png) ?? false || pasteboard.types?.contains(.tiff) ?? false
            {
                onNotice("camera.viewfinder", "Screenshot copied")
            }
        }
    }

    func pickColor() {
        closeShelves()
        let restore = stepAsideWindow()
        NSColorSampler().show { [weak self] color in
            MainActor.assumeIsolated { restore() }
            guard let color, let rgb = color.usingColorSpace(.sRGB) else { return }
            let hex = ColorHex.string(
                red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            MainActor.assumeIsolated { self?.onNotice("eyedropper.halffull", "\(hex) copied") }
        }
    }

    // MARK: System

    /// Sends the system Lock Screen shortcut (⌃⌘Q); needs Accessibility.
    func lockScreen() {
        closeShelves()
        let source = CGEventSource(stateID: .combinedSessionState)
        let qKey: CGKeyCode = 12
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: qKey, keyDown: keyDown)
            event?.flags = [.maskCommand, .maskControl]
            event?.post(tap: .cghidEventTap)
        }
    }

    func emptyTrash() {
        guard confirm("Empty the Trash?", detail: "This can't be undone.", action: "Empty Trash") else { return }
        Task {
            let ok = await Self.runAppleScript("tell application \"Finder\" to empty trash")
            onNotice(
                ok ? "trash.fill" : "exclamationmark.triangle.fill",
                ok ? "Trash emptied" : "Allow Wisp to control Finder")
        }
    }

    func toggleDoNotDisturb() {
        let name = preferences.doNotDisturbShortcut
        guard !name.isEmpty else {
            onNotice("moon.fill", "Choose a Do Not Disturb shortcut in Settings")
            return
        }
        shortcuts.run(name)
    }

    // MARK: Helpers

    private func confirm(_ title: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func runAppleScript(_ source: String) async -> Bool {
        (try? await ProcessRunner.run("/usr/bin/osascript", ["-e", source])) != nil
    }

    private static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private static var finderHidesDesktop: Bool {
        UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop").map { "\($0)" } == "0"
    }
}
