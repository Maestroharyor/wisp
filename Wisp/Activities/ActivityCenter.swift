import Foundation
import Observation
import WispCore

/// A live activity shown as a round bubble beside the main pill.
struct ActivityBubble: Equatable {
    let slot: ActivitySlot
    let activity: Activity
}

/// Observable wrapper around `ActivityQueue`: publishes the activity for the main pill
/// and the bubbles beside it, and wakes itself when a transient one expires.
@MainActor
@Observable
final class ActivityCenter {
    /// Sticky activities that a glyph can sum up, so they can sit in a bubble.
    static let bubbleSlots: Set<ActivitySlot> = [.media, .timer, .agent, .meeting]
    static let bubbleLimit = 2

    private(set) var current: Activity?
    /// Highest priority first: the first sits right of the pill, the second left.
    private(set) var bubbles: [ActivityBubble] = []

    /// The bubble the user clicked, kept in the pill while it lasts.
    @ObservationIgnored private var pinned: ActivitySlot?

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

    /// Swaps a bubble into the main pill.
    func pin(_ slot: ActivitySlot) {
        pinned = slot
        refresh()
    }

    private func refresh() {
        let now = Date.now
        queue.prune(now: now)
        if let pinned, queue.live(id: pinned.rawValue, now: now) == nil { self.pinned = nil }
        let arrangement = queue.arrangement(
            now: now, pinned: pinned?.rawValue, bubbleIDs: Set(Self.bubbleSlots.map(\.rawValue)),
            limit: Self.bubbleLimit)
        let next = arrangement.primary?.payload
        if next != current { current = next }
        let nextBubbles = arrangement.bubbles.compactMap { entry in
            ActivitySlot(rawValue: entry.id).map { ActivityBubble(slot: $0, activity: entry.payload) }
        }
        if nextBubbles != bubbles { bubbles = nextBubbles }

        expiryTask?.cancel()
        guard let expiry = queue.nextExpiry(after: now) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiry.timeIntervalSinceNow + 0.01))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
