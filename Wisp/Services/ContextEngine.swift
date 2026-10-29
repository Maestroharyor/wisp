import AppKit
import WispCore

/// Watches what the user is doing (front app, music, Focus, agents, displays) and
/// switches profiles by the rules in Settings. A manual choice holds for 30 minutes.
@MainActor
final class ContextEngine {
    /// Called with the profile to apply and whether the user picked it.
    var onSwitch: (Profile, Bool) -> Void = { _, _ in }

    private let preferences: Preferences
    private var state = ContextState()
    private var engine: ContextEngineState
    private var recheck: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private static let debounce: TimeInterval = 2
    private static let manualHold: TimeInterval = 30 * 60

    init(preferences: Preferences) {
        self.preferences = preferences
        engine = ContextEngineState(
            debounce: Self.debounce, manualHold: Self.manualHold, active: preferences.activeProfile)
    }

    func start() {
        state.frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        state.externalDisplay = NSScreen.screens.count > 1
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    self?.update { $0.frontApp = id }
                }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.update { $0.externalDisplay = NSScreen.screens.count > 1 } }
            })
    }

    func update(_ change: (inout ContextState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        evaluate()
    }

    /// Hyper+digit, the menu or Settings: apply now and hold it.
    func choose(_ profile: Profile) {
        engine.chooseManually(profile.name, at: .now)
        recheck?.cancel()
        onSwitch(profile, true)
    }

    func choose(digit: Int) {
        let profiles = preferences.profiles
        guard let index = Profile.index(forDigit: digit, count: profiles.count) else { return }
        choose(profiles[index])
    }

    private func evaluate() {
        guard preferences.contextAware else { return }
        let candidate = ContextRules.match(preferences.contextRules, state: state)
        if let name = engine.propose(candidate, at: .now) {
            recheck?.cancel()
            if let profile = preferences.profile(named: name) { onSwitch(profile, false) }
            return
        }
        // A new match has to hold for the debounce; look again once it has.
        recheck?.cancel()
        guard engine.isPending else { return }
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.debounce + 0.1))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }
}
