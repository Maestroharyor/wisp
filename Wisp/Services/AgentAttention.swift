import AppKit
import Observation
import WispCore

/// When agent alerts should stay out of the way, and what to say when the user comes back:
/// quiet hours and the one-hour mute (`AlertQuiet`), skipping a sound or Done card for a
/// session whose terminal is already in front (`AgentLooking`), and noticing time away
/// (`AwayTracker`) for the "While you were away" card.
@MainActor
@Observable
final class AgentAttention {
    /// "Mute for 1 h" in the Agents view: every agent alert group is quiet until then.
    private(set) var mutedUntil: Date? {
        didSet { defaults.set(mutedUntil?.timeIntervalSince1970 ?? 0, forKey: Self.mutedKey) }
    }
    /// Bumped when the away card asks for the history; the Agents view opens it.
    private(set) var historyRequests = 0
    /// Set with `historyRequests` and taken by the Agents view, so one opened after the request
    /// (the widget wasn't on screen yet) still shows the history.
    @ObservationIgnored private var historyPending = false

    /// The time away, when the user comes back after `AwayTracker.minimum`, with the spend
    /// baseline from when it began.
    @ObservationIgnored var onReturn: (DateInterval, SpendBaseline?) -> Void = { _, _ in }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let hub: AgentHub
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tracker = AwayTracker()
    @ObservationIgnored private var spendSamples = SpendSamples()
    /// The day's spend when the current time away began, taken then: the samples only reach
    /// back half an hour.
    @ObservationIgnored private var awayBaseline: SpendBaseline?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var historyExpiry: Task<Void, Never>?
    /// Recent looking answers per session, in flight or done.
    @ObservationIgnored private var looks: [String: (started: Date, answer: Task<Bool, Never>)] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var muteEnd: Task<Void, Never>?

    private static let mutedKey = "agentMutedUntil"
    static let muteLength: TimeInterval = 3600
    /// How often idle time is read: once a minute, and every few seconds while away for want of
    /// input, so the card comes soon after the user is back.
    private static let idleCheck: Duration = .seconds(60)
    private static let idleAwayCheck: Duration = .seconds(5)
    /// The longest a tab check may take; past it the app in front decides alone.
    private static let probeTimeout: Duration = .seconds(1)
    /// Seconds a looking answer is reused for the same session.
    private static let lookReuse: TimeInterval = 3
    /// A wake is counted this long after it, once a lock that came with the sleep has been
    /// confirmed (`SessionLock.settle`), so the card doesn't go behind the lock screen.
    private static let wakeSettle: Duration = .seconds(3)
    /// A history request no Agents view took by then is dropped, so it can't surprise a later visit.
    private static let historyWait: Duration = .seconds(5)

    init(preferences: Preferences, hub: AgentHub, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.hub = hub
        self.defaults = defaults
        let saved = defaults.double(forKey: Self.mutedKey)
        mutedUntil = AlertQuiet.activeMute(saved > 0 ? Date(timeIntervalSince1970: saved) : nil, now: .now)
        scheduleMuteEnd()
    }

    // MARK: Quiet

    func isQuiet(_ group: AgentAlertGroup) -> Bool {
        AlertQuiet.isQuiet(group, hours: preferences.quietHours, mutedUntil: mutedUntil, now: .now)
    }

    func mute() {
        mutedUntil = Date.now.addingTimeInterval(Self.muteLength)
        scheduleMuteEnd()
    }

    func unmute() {
        mutedUntil = nil
        scheduleMuteEnd()
    }

    /// Clears the mute when it runs out, so the header shows it ended.
    private func scheduleMuteEnd() {
        muteEnd?.cancel()
        guard let end = mutedUntil else { return }
        muteEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.mutedUntil = nil
        }
    }

    // MARK: Looking

    /// Whether the user is looking at the session's terminal, so its sound or Done card can be
    /// skipped. The app in front decides at once; where the selected tab can be read (iTerm2 and
    /// Terminal, already allowed under Automation) that read takes a moment and runs only while
    /// the app is in front. Limits alerts never count as looked at.
    /// One finish asks up to three times (sound, card, summary), so an answer is shared for a
    /// few seconds and they all agree.
    func isLooking(at sessionID: String?, group: AgentAlertGroup) async -> Bool {
        guard AgentLooking.applies(to: group), let sessionID, let session = hub.sessions.session(sessionID) else {
            return false
        }
        // Asleep, locked or idle: nobody is looking, whatever is in front.
        guard tracker.since == nil else { return false }
        let now = Date.now
        looks = looks.filter { now.timeIntervalSince($0.value.started) < Self.lookReuse }
        if let look = looks[sessionID] { return await look.answer.value }
        let answer = Task { await Self.look(at: session) }
        looks[sessionID] = (now, answer)
        return await answer.value
    }

    private static func look(at session: AgentSession) async -> Bool {
        let app = session.terminal
        guard
            AgentLooking.isLooking(
                frontmost: frontmost, sessionApp: app, sessionTTY: nil, activeTTY: nil,
                idleSeconds: PushService.idleSeconds)
        else { return false }
        guard let probe = AgentLooking.probe(context: session.terminalContext, sessionApp: app) else { return true }
        let active = await activeTTY(probe)
        return AgentLooking.isLooking(
            frontmost: frontmost, sessionApp: probe.app, sessionTTY: probe.tty, activeTTY: active,
            idleSeconds: PushService.idleSeconds)
    }

    private static var frontmost: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    /// The front tab's tty, or nil when Wisp may not script the app yet or it didn't answer.
    private static func activeTTY(_ probe: AgentLooking.Probe) async -> String? {
        guard await AutomationPermission.isAllowed(probe.app) else { return nil }
        return await AppleScriptRunner.run(probe.script, timeout: probeTimeout)
    }

    // MARK: Away

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.wakeTask?.cancel()
                    self?.handle(.slept)
                }
            })
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wokeSoon() }
            })
        checkIdle()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        idleTask?.cancel()
        idleTask = nil
        wakeTask?.cancel()
        muteEnd?.cancel()
        historyExpiry?.cancel()
    }

    private func wokeSoon() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.wakeSettle)
            guard !Task.isCancelled else { return }
            self?.handle(.woke)
        }
    }

    /// Locks and unlocks from `SessionMonitor`.
    func handle(_ event: AwayTracker.Event) {
        let wasAway = tracker.since != nil
        let away = tracker.handle(event, at: .now)
        if !wasAway, let since = tracker.since { awayBaseline = spendSamples.baseline(at: since) }
        if tracker.since == nil {
            let baseline = awayBaseline
            awayBaseline = nil
            if let away { onReturn(away, baseline) }
        }
    }

    private func checkIdle() {
        idleTask?.cancel()
        let now = Date.now
        spendSamples.record(total: hub.spend.total(on: now), at: now)
        handle(.idle(PushService.idleSeconds))
        let wait = tracker.isIdleAway ? Self.idleAwayCheck : Self.idleCheck
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.checkIdle()
        }
    }

    // MARK: History

    /// Asks the Agents view to show the history.
    func requestHistory() {
        historyPending = true
        historyRequests += 1
        historyExpiry?.cancel()
        historyExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.historyWait)
            guard !Task.isCancelled else { return }
            self?.historyPending = false
        }
    }

    /// True once per request, for the Agents view that shows it.
    func takeHistoryRequest() -> Bool {
        defer { historyPending = false }
        return historyPending
    }
}
