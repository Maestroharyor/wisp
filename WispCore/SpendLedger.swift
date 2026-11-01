import Foundation

/// The cost already counted for each agent transcript, so reading a transcript again
/// (after Wisp relaunches, a session is pruned or resumed) only adds what's new.
public struct SpendLedger: Codable, Equatable, Sendable {
    public static let keptSeconds: TimeInterval = 30 * 86_400

    private struct Entry: Codable, Equatable {
        var cost: Double
        var seen: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// Records `total`, the transcript's whole cost so far, and returns the part not counted before.
    public mutating func record(total: Double, for transcript: String, at date: Date) -> Double {
        let counted = entries[transcript]?.cost ?? 0
        entries[transcript] = Entry(cost: max(total, counted), seen: date)
        entries = entries.filter { date.timeIntervalSince($0.value.seen) < Self.keptSeconds }
        return max(0, total - counted)
    }

    public func counted(for transcript: String) -> Double {
        entries[transcript]?.cost ?? 0
    }
}
