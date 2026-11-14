import Foundation
import Observation
import WispCore

/// Coding agents Wisp sees only by their process (`KnownAgents`), shown as Running sessions with
/// their folder. It scans the process table every 15 seconds, and only while Monitor is on and
/// an Agents view is showing or an agent it found is still running, so nothing runs in the
/// background otherwise. Agents whose hooks are installed are left to their hooks.
@MainActor
@Observable
final class AgentMonitor {
    static let interval: Duration = .seconds(15)

    private(set) var sessions: [MonitoredSession] = []
    /// The Monitor setting. Off clears the list and stops scanning.
    var enabled = true {
        didSet {
            guard enabled != oldValue else { return }
            if !enabled { sessions = [] }
            update()
        }
    }
    /// Adapter ids whose hooks are installed; their processes aren't shown.
    var connected: Set<String> = [] {
        didSet { if connected != oldValue { sessions = sessions.filter(isShown) } }
    }
    /// Whether the shelf or the Wisp window, where the Agents views live, is on screen. Set by
    /// AppDelegate; a view that left without saying so can't keep the scan going past it.
    @ObservationIgnored var surfaceVisible: @MainActor () -> Bool = { true }

    @ObservationIgnored private var schedule = MonitorScan()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Bumped for each loop, so an old loop ending doesn't forget a newer one.
    @ObservationIgnored private var generation = 0

    /// An Agents view came on screen: scan now, then keep scanning while it shows.
    func viewAppeared() {
        schedule.viewAppeared()
        update(scanNow: true)
    }

    func viewDisappeared() {
        schedule.viewDisappeared()
        update()
    }

    private var wanted: Bool { enabled && schedule.wanted(tracking: !sessions.isEmpty) }

    /// Starts or stops the scan loop to match `wanted`.
    private func update(scanNow: Bool = false) {
        guard wanted else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        if scanNow { pollTask?.cancel() } else if pollTask != nil { return }
        generation += 1
        let loop = generation
        pollTask = Task { [weak self] in
            // A view that just appeared gets its list at once, even mid-animation.
            var first = scanNow
            while !Task.isCancelled {
                guard let self else { return }
                let step = first ? .scan : self.nextStep()
                first = false
                switch step {
                case .scan: await self.scan()
                case .wait: break
                case .stop:
                    // Stopped by itself (the last agent quit, no view on screen): let the next
                    // view start a new loop.
                    if self.generation == loop { self.pollTask = nil }
                    return
                }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func nextStep() -> MonitorScan.Step {
        guard enabled else { return .stop }
        return schedule.tick(surfaceVisible: surfaceVisible(), tracking: !sessions.isEmpty, now: .now)
    }

    private func scan() async {
        let found = await Task.detached(priority: .utility) { ProcessScan.sessions() }.value
        guard enabled, !Task.isCancelled else { return }
        let shown = found.filter(isShown)
        if shown != sessions { sessions = shown }
    }

    private func isShown(_ session: MonitoredSession) -> Bool {
        session.agent.adapterID.map { !connected.contains($0) } ?? true
    }
}
