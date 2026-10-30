import Foundation

/// One live activity waiting to be shown beside the notch.
public struct ActivityEntry<Payload: Sendable>: Sendable {
    public let id: String
    public var priority: Int
    /// Nil means sticky: it stays until removed (media, running timer).
    public var expiresAt: Date?
    public var payload: Payload
    public var updatedAt: Date
}

/// Decides which live activity the notch shows. Transient items (HUDs) carry an
/// expiry and a higher priority, so they pre-empt sticky ones and then hand back.
public struct ActivityQueue<Payload: Sendable>: Sendable {
    public private(set) var entries: [String: ActivityEntry<Payload>] = [:]

    public init() {}

    /// Adds or refreshes an activity. Posting the same id again updates it in place.
    public mutating func post(
        id: String,
        priority: Int,
        duration: TimeInterval?,
        payload: Payload,
        now: Date
    ) {
        entries[id] = ActivityEntry(
            id: id,
            priority: priority,
            expiresAt: duration.map { now.addingTimeInterval($0) },
            payload: payload,
            updatedAt: now
        )
    }

    public mutating func remove(id: String) {
        entries[id] = nil
    }

    public mutating func prune(now: Date) {
        entries = entries.filter { _, entry in entry.expiresAt.map { $0 > now } ?? true }
    }

    /// Highest priority wins; among equals, the most recently updated.
    public func current(now: Date) -> ActivityEntry<Payload>? {
        entries.values
            .filter { entry in entry.expiresAt.map { $0 > now } ?? true }
            .max { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.updatedAt < rhs.updatedAt : lhs.priority < rhs.priority
            }
    }

    /// The entry for `id` if it is still live, even when another one is showing.
    public func live(id: String, now: Date) -> ActivityEntry<Payload>? {
        guard let entry = entries[id], entry.expiresAt.map({ $0 > now }) ?? true else { return nil }
        return entry
    }

    /// When the next transient activity ends, so the owner can schedule a refresh.
    public func nextExpiry(after now: Date) -> Date? {
        entries.values.compactMap(\.expiresAt).filter { $0 > now }.min()
    }
}
