import AppKit
import WispCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences.shared
    let services: AppServices
    let hotkeys: HotkeyCenter
    private let coordinator: NotchCoordinator
    private let settings: SettingsWindowController
    private let clipboardPanel: ClipboardPanelController
    private let onboarding: OnboardingWindowController
    private var terminationSignal: DispatchSourceSignal?

    override init() {
        services = AppServices(preferences: Preferences.shared)
        hotkeys = HotkeyCenter(preferences: Preferences.shared)
        coordinator = NotchCoordinator(services: services)
        settings = SettingsWindowController(services: services, hotkeys: hotkeys)
        clipboardPanel = ClipboardPanelController(services: services)
        onboarding = OnboardingWindowController(services: services)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to a helper (media bridge, zip) that just exited must fail with an
        // error, not kill Wisp with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        services.openSettings = { [weak self] in self?.showSettings() }
        services.openClipboard = { [weak self] in self?.toggleClipboard() }
        services.openSetup = { [weak self] in self?.onboarding.show() }
        services.openShelf = { [weak self] page in self?.coordinator.openShelf(page: page) }
        services.openWidget = { [weak self] kind in self?.coordinator.openWidget(kind) }
        services.formUnderPointer = { [weak self] in self?.coordinator.formUnderPointer() ?? (.notch, false) }
        services.setForm = { [weak self] form in self?.coordinator.setForm(form) }
        services.cycleForm = { [weak self] in self?.coordinator.cycleForm() }
        services.start()
        coordinator.start()
        // The Window form opens with Wisp, as any app's window would.
        if preferences.windowForm { services.shelfWindow.activateShell() }
        services.automation.acceptLinks()
        hotkeys.onToggle = { [weak self] in self?.toggleShelf() }
        hotkeys.onClipboard = { [weak self] in self?.toggleClipboard() }
        hotkeys.onProfileDigit = { [weak self] digit in self?.services.context.choose(digit: digit) }
        hotkeys.onRing = { [weak self] in self?.services.ring.toggle(at: NSEvent.mouseLocation) }
        hotkeys.onCycleForm = { [weak self] in self?.services.cycleForm() }
        hotkeys.onApprovalKey = { [weak self] keyCode in
            guard let services = self?.services else { return false }
            // Out of sight (a HUD over the card): swallowed and ignored, so it neither answers
            // nor types into the front app.
            guard services.approvalOnScreen else { return services.agents.keyHasAction(keyCode) }
            return services.agents.answerKey(keyCode)
        }
        hotkeys.onApprovalKeyUp = { [weak self] keyCode in self?.services.agents.releaseKey(keyCode) }
        services.approvalCardChanged = { [weak self] prompt in self?.hotkeys.setApprovalCard(prompt) }
        services.agents.keysUseHyper = { [weak self] in self?.hotkeys.approvalKeysUseHyper ?? false }
        services.isShelfOpen = { [weak self] in self?.coordinator.hasOpenShelf ?? false }
        services.releaseNotchKey = { [weak self] in self?.coordinator.releaseKey() }
        hotkeys.onDictation = { [weak self] event in self?.services.dictation.handle(event) }
        services.dictation.onTap = { [weak self] in self?.toggleShelf() }
        services.dictation.resolveTarget = { [weak self] in self?.coordinator.dictationTarget() ?? .focusedApp }
        services.dictation.deliverInWisp = { [weak self] text, target in
            self?.coordinator.deliverDictation(text, to: target) ?? false
        }
        hotkeys.start()
        services.ringTrigger.start()
        handleTerminationSignal()
        if !preferences.onboarded { onboarding.show() }
        #if DEBUG
            // Lets scripts drive Wisp for visual checks without synthetic input.
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.ayomideodewale.wisp.debug.toggleShelf"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.toggleShelf() }
            }
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.ayomideodewale.wisp.debug.miniPlayer"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.services.miniPlayer.toggle() }
            }
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.ayomideodewale.wisp.debug.ring"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.services.ring.toggle(at: NSEvent.mouseLocation) }
            }
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.ayomideodewale.wisp.debug.cycleForm"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.services.cycleForm() }
            }
            // Toggle stand-in activities, to film show, hide and bubble motion.
            for kind in ["timer", "agent", "card"] {
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name("com.ayomideodewale.wisp.debug.\(kind)"), object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.toggleDebugActivity(kind) }
                }
            }
        #endif
    }

    /// Launching Wisp again while it runs (Finder, Spotlight, `open`) shows Settings,
    /// so Settings stays reachable even when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// `wisp://` links. Opening one launches Wisp first if needed, after which this runs.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { services.automation.open(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
        // Caps Lock must work again after Wisp quits.
        hotkeys.shutdown()
    }

    func toggleShelf() {
        coordinator.toggleShelf()
    }

    #if DEBUG
        private var debugActivities: Set<String> = []

        private func toggleDebugActivity(_ kind: String) {
            if kind == "card" {
                // A short card, to check closing, swiping away and holding it with the pointer.
                services.activities.post(.timerDone(label: "Debug"), slot: .timerDone, duration: 5)
                return
            }
            let slot: ActivitySlot = kind == "timer" ? .timer : .agent
            if debugActivities.remove(kind) != nil {
                services.activities.remove(slot)
                return
            }
            debugActivities.insert(kind)
            if kind == "timer" {
                var countdown = Countdown(duration: 300)
                countdown.start(now: .now)
                services.activities.post(.timer(label: "Debug", countdown: countdown), slot: slot, duration: nil)
            } else {
                let status = AgentStatus(
                    sessionID: "debug", project: "wisp", source: .claude, state: .running, started: .now)
                services.activities.post(.agent(status), slot: slot, duration: nil)
            }
        }
    #endif

    func toggleClipboard() {
        clipboardPanel.toggle()
    }

    func showSettings() {
        settings.show()
    }

    /// `kill`/`pkill` send SIGTERM, which skips applicationWillTerminate. Route it
    /// through a normal quit so the Caps Lock remap is always undone.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }
}
