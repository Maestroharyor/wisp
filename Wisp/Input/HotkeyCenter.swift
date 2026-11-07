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
    @ObservationIgnored var onRing: @MainActor () -> Void = {}
    @ObservationIgnored var onCycleForm: @MainActor () -> Void = {}
    /// The ring's shortcut couldn't be registered, for example because Wisp already uses it.
    private(set) var ringHotkeyTaken = false
    /// Hyper+1…9 picks a profile.
    @ObservationIgnored var onProfileDigit: @MainActor (Int) -> Void = { _ in }
    /// Y, N or a digit for the approval card on screen (`ApprovalKeys`); false leaves the key
    /// to the other shortcuts.
    @ObservationIgnored var onApprovalKey: @MainActor (UInt16) -> Bool = { _ in false }
    /// The key of a swallowed chord or fallback shortcut came back up.
    @ObservationIgnored var onApprovalKeyUp: @MainActor (UInt16) -> Void = { _ in }
    /// The dictation key held with Hyper: pressed, let go or cancelled.
    @ObservationIgnored var onDictation: @MainActor (HoldKey.Event) -> Void = { _ in }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let remapper = CapsLockRemapper()
    @ObservationIgnored private let tap = HyperKeyTap()
    @ObservationIgnored private let carbon = CarbonHotkey(id: 1)
    @ObservationIgnored private let clipboardCarbon = CarbonHotkey(id: 2)
    @ObservationIgnored private let ringCarbon = CarbonHotkey(id: 3)
    /// ⌃⌥⌘Y, N and 1 to 9 without Hyper, registered only while a card shows.
    /// One per key in `ApprovalKeys.allFallbackKeys`, so each key keeps its Carbon id.
    @ObservationIgnored private let approvalCarbons = ApprovalKeys.allFallbackKeys.indices.map {
        CarbonHotkey(id: 10 + UInt32($0))
    }
    /// The kind of card on screen; nil when none shows.
    @ObservationIgnored private var approvalPrompt: PermissionPrompt?
    /// The fallback keys registered now.
    @ObservationIgnored private var fallbackKeys: [UInt16] = []
    @ObservationIgnored private var keyboardWatcher: HIDDeviceWatcher?
    @ObservationIgnored private var holdDrain: Task<Void, Never>?
    @ObservationIgnored private var accessWaiter: Task<Void, Never>?
    /// Notices Accessibility being switched off while Hyper is active.
    @ObservationIgnored private var trustWatcher: Task<Void, Never>?
    /// The user switched Accessibility off while Hyper was on: don't prompt again for a choice
    /// they just made. Settings still shows the status, and turning it back on resumes.
    @ObservationIgnored private var accessRevoked = false
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "hotkey")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// One task reads the tap's hold events in order and hands them to dictation.
    private func drainHoldEvents() {
        guard holdDrain == nil else { return }
        let events = tap.holdEvents
        holdDrain = Task { [weak self] in
            for await event in events { self?.onDictation(event) }
        }
    }

    func start() {
        drainHoldEvents()
        configure()
        observePreferences()
    }

    /// Restores Caps Lock. Call on quit.
    func shutdown() {
        tap.finishHoldEvents()
        accessWaiter?.cancel()
        trustWatcher?.cancel()
        tap.stop()
        carbon.unregister()
        clipboardCarbon.unregister()
        ringCarbon.unregister()
        unregisterApprovalFallback()
        keyboardWatcher?.stop()
        do {
            try remapper.disable()
        } catch {
            log.error("could not restore Caps Lock: \(String(describing: error), privacy: .public)")
        }
    }

    private func configure() {
        accessWaiter?.cancel()
        trustWatcher?.cancel()
        tap.stop()
        carbon.unregister()
        clipboardCarbon.unregister()
        ringCarbon.unregister()
        if let ringHotkey = preferences.ringHotkey {
            ringHotkeyTaken = !ringCarbon.register(ringHotkey) { [weak self] in self?.onRing() }
        } else {
            ringHotkeyTaken = false
        }
        defer { updateApprovalFallback() }

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
            // During first-launch setup, the setup window asks, with an explanation.
            if preferences.onboarded, !accessRevoked { AccessibilityPermission.requestAccess() }
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
            keyboardWatcher = HIDDeviceWatcher(matching: HIDDeviceWatcher.keyboards) { [weak self] in
                self?.reapplyRemap()
            }
        }
        keyboardWatcher?.start()

        tap.quickPressTogglesCapsLock = preferences.quickPressTogglesCapsLock
        tap.onChordReleased = { [weak self] keyCode in self?.onApprovalKeyUp(keyCode) }
        tap.holdKey = preferences.dictationEnabled ? preferences.dictationKey.keyCode : nil
        tap.onHyperChord = { [weak self] keyCode in
            switch keyCode {
            case hotkey.keyCode: self?.onToggle()
            case KeyCodes.v: self?.onClipboard()
            case KeyCodes.r: self?.onRing()
            case KeyCodes.f: self?.onCycleForm()
            default:
                if self?.onApprovalKey(keyCode) == true { return true }
                guard let digit = KeyCodes.digit(forKeyCode: keyCode) else { return false }
                self?.onProfileDigit(digit)
            }
            return true
        }
        guard tap.start() else {
            // Without the tap, a remapped Caps Lock would send F18 and do nothing.
            disableRemap()
            status = .unavailable("Could not start the keyboard tap")
            return
        }
        status = .active
        accessRevoked = false
        watchTrust()
    }

    /// The kind of approval or question card on screen (nil when none), for the ⌃⌥⌘ fallback.
    func setApprovalCard(_ prompt: PermissionPrompt?) {
        guard prompt != approvalPrompt else { return }
        approvalPrompt = prompt
        updateApprovalFallback()
    }

    /// Cards are answered with Hyper (Caps Lock) rather than the ⌃⌥⌘ fallback, for their key hints.
    var approvalKeysUseHyper: Bool { preferences.hotkey.usesHyper && status == .active }

    /// The fallback holds only the keys the card on screen uses, only while it shows, and
    /// only when the Hyper tap isn't there to answer.
    private func updateApprovalFallback() {
        guard let prompt = approvalPrompt, !approvalKeysUseHyper else {
            unregisterApprovalFallback()
            return
        }
        let wanted = ApprovalKeys.fallbackHotkeys(for: prompt)
        guard wanted.map(\.keyCode) != fallbackKeys else { return }
        unregisterApprovalFallback()
        for hotkey in wanted {
            guard let slot = ApprovalKeys.allFallbackKeys.firstIndex(of: hotkey.keyCode) else { continue }
            let registered = approvalCarbons[slot].register(
                hotkey, onRelease: { [weak self] in self?.onApprovalKeyUp(hotkey.keyCode) },
                action: { [weak self] in _ = self?.onApprovalKey(hotkey.keyCode) })
            if registered { fallbackKeys.append(hotkey.keyCode) }
        }
    }

    /// A key held while its shortcut goes away never reports coming up, so it counts as up.
    private func unregisterApprovalFallback() {
        approvalCarbons.forEach { $0.unregister() }
        fallbackKeys.forEach(onApprovalKeyUp)
        fallbackKeys = []
    }

    /// Without Accessibility the tap gets no events, so a remapped Caps Lock would send F18
    /// and do nothing. macOS doesn't announce the change, so check every few seconds.
    private func watchTrust() {
        trustWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, !AccessibilityPermission.isTrusted else { continue }
                self?.log.notice("Accessibility was turned off; restoring Caps Lock")
                self?.accessRevoked = true
                self?.configure()
                return
            }
        }
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
            _ = preferences.ringHotkey
            _ = preferences.dictationEnabled
            _ = preferences.dictationKey
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.configure()
                self?.observePreferences()
            }
        }
    }
}
