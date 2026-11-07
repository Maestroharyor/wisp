import Foundation

/// The activities scripts and Shortcuts have posted. The one touched last shows. Each lasts
/// `lifetime` past its last start or update, so a script that dies without `end` can't keep
/// the notch busy for good.
public struct ExternalActivities: Equatable, Sendable {
    public static let lifetime: TimeInterval = 15 * 60
    /// More than this many at once drops the oldest, so a runaway loop stays bounded.
    public static let limit = 8

    private struct Entry: Equatable, Sendable {
        var activity: ExternalActivity
        var touched: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// False when an update named an activity that isn't showing and gave no title to start it.
    @discardableResult
    public mutating func apply(_ action: ExternalActivityAction, now: Date) -> Bool {
        prune(now: now)
        defer {
            while entries.count > Self.limit, let oldest = entries.values.min(by: { $0.touched < $1.touched }) {
                entries[oldest.activity.id] = nil
            }
        }
        switch action {
        case .start(let activity):
            entries[activity.id] = Entry(activity: activity, touched: now)
        case .update(let update):
            if var entry = entries[update.id] {
                if let title = update.title { entry.activity.title = title }
                if let symbol = update.symbol { entry.activity.symbol = symbol }
                if let progress = update.progress { entry.activity.progress = progress }
                entry.touched = now
                entries[update.id] = entry
            } else if let title = update.title {
                // An update for one Wisp never saw (it restarted, or the start was lost).
                let activity = ExternalActivity(
                    id: update.id, title: title, symbol: update.symbol ?? ExternalActivity.defaultSymbol,
                    progress: update.progress)
                entries[update.id] = Entry(activity: activity, touched: now)
            } else {
                return false
            }
        case .end(let id):
            entries[id] = nil
        }
        return true
    }

    public static func notShowing(_ id: String) -> String {
        "No activity \(id) is showing. Start it, or include a title in the update."
    }

    public mutating func prune(now: Date) {
        entries = entries.filter { isLive($0.value, now: now) }
    }

    /// The live activity touched last.
    public func current(now: Date) -> ExternalActivity? {
        entries.values.filter { isLive($0, now: now) }.max { $0.touched < $1.touched }?.activity
    }

    /// When the next live activity runs out, so the caller can look again then.
    public func expiry(now: Date) -> Date? {
        entries.values.filter { isLive($0, now: now) }.map { $0.touched + Self.lifetime }.min()
    }

    private func isLive(_ entry: Entry, now: Date) -> Bool { now < entry.touched + Self.lifetime }
}
