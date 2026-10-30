import Foundation
import Observation
import WispCore

/// Observable wrapper around `ActivityQueue`: publishes the activity to show and
/// wakes itself when a transient one expires.
@MainActor
@Observable
final class ActivityCenter {
    private(set) var current: Activity?
    /// Music still playing behind an agent run: the pill shows both, agent left and music right.
    private(set) var companion: Activity?

    @ObservationIgnored private var queue = ActivityQueue<Activity>()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    /// Posts or refreshes the activity for a slot. `duration` nil keeps it until removed.
    func post(_ activity: Activity, slot: ActivitySlot, duration: TimeInterval?) {
        queue.post(id: slot.rawValue, priority: slot.priority, duration: duration, payload: activity, now: .now)
        refresh()
    }

    func remove(_ slot: ActivitySlot) {
        guard queue.entries[slot.rawValue] != nil else { return }
        queue.remove(id: slot.rawValue)
        refresh()
    }

    private func refresh() {
        let now = Date.now
        queue.prune(now: now)
        let next = queue.current(now: now)?.payload
        if next != current { current = next }
        let behind: Activity? =
            if case .agent = next, queue.live(id: ActivitySlot.media.rawValue, now: now) != nil { .media } else { nil }
        if behind != companion { companion = behind }

        expiryTask?.cancel()
        guard let expiry = queue.nextExpiry(after: now) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiry.timeIntervalSinceNow + 0.01))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
