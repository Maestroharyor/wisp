import Foundation

/// The cost already counted for each agent transcript, so reading a transcript again
/// (after Wisp relaunches, a session is pruned or resumed) only adds what's new.
public struct SpendLedger: Codable, Equatable, Sendable {
    public static let keptSeconds: TimeInterval = 30 * 86_400

    private struct Entry: Codable, Equatable {
        /// For a transcript, the highest cost counted. For a session, the last total Claude
        /// Code reported in its current run.
        var cost: Double
        var seen: Date
        /// For a session: an estimate already counted for its transcript, not yet matched by
        /// real cost. Absent in entries saved before sessions had them.
        var credit: Double?
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

    /// Records Claude Code's own `total` for a session and returns the part not counted
    /// before. The total counts from when Claude Code started, so a resumed session can
    /// report less than last time: a drop starts a new run, counted in full. The first time,
    /// whatever was already estimated for the transcript is a credit used up before anything
    /// new counts, so an estimate counted on Stop isn't counted twice.
    public mutating func record(total: Double, session: String, transcript: String?, at date: Date) -> Double {
        let key = "session:" + session
        let entry = entries[key] ?? Entry(cost: 0, seen: date, credit: transcript.flatMap { entries[$0]?.cost })
        let added = total >= entry.cost ? total - entry.cost : total
        let credit = entry.credit ?? 0
        let used = min(credit, added)
        entries[key] = Entry(cost: total, seen: date, credit: credit - used)
        entries = entries.filter { date.timeIntervalSince($0.value.seen) < Self.keptSeconds }
        return added - used
    }

    /// The session's process started again (a resume), so its next total counts from zero
    /// even if Wisp wasn't running to see the cost drop. Any unused estimate credit stays.
    public mutating func startRun(session: String, at date: Date) {
        let key = "session:" + session
        guard let entry = entries[key] else { return }
        entries[key] = Entry(cost: 0, seen: date, credit: entry.credit)
    }

    public func counted(for transcript: String) -> Double {
        entries[transcript]?.cost ?? 0
    }
}
