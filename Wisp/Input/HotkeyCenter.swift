import Foundation
import OSLog
import Observation
import WispCore

/// Wires the user's shelf shortcut to either the Caps Lock (Hyper) event tap or a
/// Carbon hotkey, and keeps the Caps Lock remap in sync with the setting.
@MainActor
@Observable
final class HotkeyCenter {
    enum Status: Equatable {
        case inactive
        case active
        case needsAccessibility
        case unavailable(String)

        var message: String {
            switch self {
            case .inactive: "Not set up"
            case .active: "Active"
            case .needsAccessibility: "Waiting for Accessibility access"
            case .unavailable(let reason): reason
            }
        }
    }

    private(set) var status: Status = .inactive
    @ObservationIgnored var onToggle: @MainActor () -> Void = {}
    @ObservationIgnored var onClipboard: @MainActor () -> Void = {}
    /// Hyper+1…9 picks a profile.
    @ObservationIgnored var onProfileDigit: @MainActor (Int) -> Void = { _ in }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let remapper = CapsLockRemapper()
    @ObservationIgnored private let tap = HyperKeyTap()
    @ObservationIgnored private let carbon = CarbonHotkey(id: 1)
    @ObservationIgnored private let clipboardCarbon = CarbonHotkey(id: 2)
    @ObservationIgnored private var keyboardWatcher: KeyboardWatcher?
    @ObservationIgnored private var accessWaiter: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.maestro.wisp", category: "hotkey")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func start() {
        configure()
        observePreferences()
    }

    /// Restores Caps Lock. Call on quit.
    func shutdown() {
        accessWaiter?.cancel()
        tap.stop()
        carbon.unregister()
        clipboardCarbon.unregister()
        keyboardWatcher?.stop()
        do {
            try remapper.disable()
        } catch {
            log.error("could not restore Caps Lock: \(String(describing: error), privacy: .public)")
        }
    }

    private func configure() {
        accessWaiter?.cancel()
        tap.stop()
        carbon.unregister()
        clipboardCarbon.unregister()

        let hotkey = preferences.hotkey
        if hotkey.usesHyper {
            configureHyper(hotkey)
        } else {
            disableRemap()
            _ = clipboardCarbon.register(Hotkey.clipboardFallback) { [weak self] in self?.onClipboard() }
            status =
                carbon.register(hotkey) { [weak self] in self?.onToggle() }
                ? .active : .unavailable("\(hotkey) is used by another app")
        }
    }

    private func configureHyper(_ hotkey: Hotkey) {
        // Only remap once the tap can run; otherwise Caps Lock would go dead.
        guard AccessibilityPermission.isTrusted else {
            disableRemap()
            status = .needsAccessibility
            AccessibilityPermission.requestAccess()
            accessWaiter = Task { [weak self] in
                await AccessibilityPermission.waitUntilTrusted()
                guard !Task.isCancelled else { return }
                self?.configure()
            }
            return
        }

        do {
            try remapper.enable()
        } catch {
            status = .unavailable("Could not remap Caps Lock")
            log.error("remap failed: \(String(describing: error), privacy: .public)")
            return
        }
        if keyboardWatcher == nil {
            keyboardWatcher = KeyboardWatcher { [weak self] in self?.reapplyRemap() }
        }
        keyboardWatcher?.start()

        tap.quickPressTogglesCapsLock = preferences.quickPressTogglesCapsLock
        tap.onHyperChord = { [weak self] keyCode in
            switch keyCode {
            case hotkey.keyCode: self?.onToggle()
            case KeyCodes.v: self?.onClipboard()
            default:
                guard let digit = KeyCodes.digit(forKeyCode: keyCode) else { return false }
                self?.onProfileDigit(digit)
            }
            return true
        }
        status = tap.start() ? .active : .unavailable("Could not start the keyboard tap")
    }

    private func reapplyRemap() {
        guard preferences.hotkey.usesHyper, status == .active else { return }
        do {
            try remapper.enable()
        } catch {
            log.error("re-applying remap failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func disableRemap() {
        keyboardWatcher?.stop()
        do {
            try remapper.disable()
        } catch {
            log.error("removing remap failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func observePreferences() {
        withObservationTracking {
            _ = preferences.hotkey
            _ = preferences.quickPressTogglesCapsLock
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.configure()
                self?.observePreferences()
            }
        }
    }
}
