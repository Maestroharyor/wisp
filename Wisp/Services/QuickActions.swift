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
    private(set) var darkMode = QuickActions.systemIsDark
    private(set) var desktopHidden = QuickActions.finderHidesDesktop

    /// Posts a short notice pill.
    var onNotice: (String, String) -> Void = { _, _ in }
    /// Closes open shelves before an action that needs the screen.
    var closeShelves: () -> Void = {}

    @ObservationIgnored private var assertion: IOPMAssertionID = 0
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
            IOPMAssertionRelease(assertion)
            assertion = 0
            keepAwake = false
        } else {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Wisp Keep Awake" as CFString,
                &assertion)
            keepAwake = result == kIOReturnSuccess
        }
        onNotice(keepAwake ? "cup.and.saucer.fill" : "moon.zzz.fill", keepAwake ? "Staying awake" : "Sleep allowed")
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
        Task {
            // Let the shelf animate away first.
            try? await Task.sleep(for: .milliseconds(350))
            _ = try? await ProcessRunner.run("/usr/sbin/screencapture", ["-i", "-c"])
            if NSPasteboard.general.types?.contains(.png) ?? false
                || NSPasteboard.general.types?.contains(.tiff) ?? false
            {
                onNotice("camera.viewfinder", "Screenshot copied")
            }
        }
    }

    func pickColor() {
        closeShelves()
        NSColorSampler().show { [weak self] color in
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
