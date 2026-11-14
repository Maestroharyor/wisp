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

    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Bumped for each loop, so an old loop ending doesn't forget a newer one.
    @ObservationIgnored private var generation = 0

    /// An Agents view came on screen: scan now, then keep scanning while it shows.
    func viewAppeared() {
        viewers += 1
        update(scanNow: true)
    }

    func viewDisappeared() {
        viewers = max(0, viewers - 1)
        update()
    }

    private var wanted: Bool { enabled && (viewers > 0 || !sessions.isEmpty) }

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
            while !Task.isCancelled {
                guard let self else { return }
                guard self.wanted else {
                    // Stopped by itself (the last agent quit with no view open): let the next
                    // view start a new loop.
                    if self.generation == loop { self.pollTask = nil }
                    return
                }
                await self.scan()
                try? await Task.sleep(for: Self.interval)
            }
        }
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
