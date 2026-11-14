import Foundation

/// What agents did while the user was away, for the one card shown when they come back:
/// "While you were away: 3 finished, 1 failed, 1 needs you, $2.10".
public struct AwaySummary: Equatable, Sendable {
    public static let title = "While you were away"

    public var finished: Int
    public var failed: Int
    /// Sessions waiting on the user now, or whose requests timed out while they were gone.
    public var needsYou: Int
    /// Estimated dollars spent while away.
    public var spend: Double

    public init(finished: Int, failed: Int, needsYou: Int, spend: Double) {
        self.finished = finished
        self.failed = failed
        self.needsYou = needsYou
        self.spend = spend
    }

    /// Runs from the session history that ended inside `during` (a quit without ending is a
    /// failure; a run that ended waiting isn't a finish), `waiting` (live sessions waiting on the
    /// user now, with when the wait began; only waits that began while away count) and requests
    /// from the approval log that timed out. A run counts once however many turns it finished.
    public static func build(
        records: [SessionRecord], approvals: [ApprovalRecord], waiting: [String: Date], spend: Double,
        during: DateInterval
    ) -> AwaySummary {
        let ended = records.filter { during.contains($0.ended) }
        let failed = ended.filter { $0.exited == true }.count
        let finished = ended.filter { $0.exited != true && !$0.endedWaiting }.count
        let timedOut = approvals.filter { $0.outcome == .timedOut && during.contains($0.date) }.map(\.sessionID)
        let newWaits = waiting.filter { during.contains($0.value) }.keys
        return AwaySummary(
            finished: finished, failed: failed, needsYou: Set(newWaits).union(timedOut).count, spend: max(spend, 0))
    }

    /// Spend under a cent rounds to nothing, so it alone doesn't make a card.
    public var isEmpty: Bool { finished == 0 && failed == 0 && needsYou == 0 && spend < 0.005 }

    public var detail: String {
        var parts: [String] = []
        if finished > 0 { parts.append("\(finished) finished") }
        if failed > 0 { parts.append("\(failed) failed") }
        if needsYou > 0 { parts.append("\(needsYou) \(needsYou == 1 ? "needs" : "need") you") }
        if spend >= 0.005 { parts.append(String(format: "$%.2f", spend)) }
        return parts.joined(separator: ", ")
    }

    public var text: String { "\(Self.title): \(detail)" }

    /// Dollars spent since `baseline`: the rest of its day, then each whole day after it up to `now`.
    public static func spent(
        _ spend: DailySpend, since baseline: SpendBaseline, now: Date, calendar: Calendar = .current
    )
        -> Double
    {
        var total = spend.total(on: baseline.date, calendar: calendar) - baseline.total
        var day = calendar.startOfDay(for: baseline.date)
        let last = calendar.startOfDay(for: now)
        while day < last, let next = calendar.date(byAdding: .day, value: 1, to: day) {
            day = next
            total += spend.total(on: day, calendar: calendar)
        }
        return max(total, 0)
    }
}

/// The day's estimated spend at a moment, to measure spend from.
public struct SpendBaseline: Equatable, Sendable {
    public let date: Date
    /// That day's total at `date`.
    public let total: Double

    public init(date: Date, total: Double) {
        self.date = date
        self.total = total
    }
}

/// The day's spend read every minute or so for the last half hour, so the away time can be
/// measured from when it began (idle is only noticed 15 minutes in).
public struct SpendSamples: Sendable {
    public static let kept: TimeInterval = 30 * 60

    private var samples: [SpendBaseline] = []

    public init() {}

    public var count: Int { samples.count }

    public mutating func record(total: Double, at date: Date) {
        samples.append(SpendBaseline(date: date, total: total))
        samples.removeAll { date.timeIntervalSince($0.date) > Self.kept }
    }

    /// The last reading at or before `date`, else the oldest kept.
    public func baseline(at date: Date) -> SpendBaseline? {
        samples.last { $0.date <= date } ?? samples.first
    }
}

/// Tells when the user left and came back: the Mac slept, the screen locked, or there was no
/// input for `minimum`. Coming back after `minimum` or longer gives the time away.
public struct AwayTracker: Sendable {
    public enum Event: Sendable {
        case slept
        case woke
        case locked
        case unlocked
        /// Seconds since the last keyboard, mouse or trackpad input.
        case idle(TimeInterval)
    }

    public static let minimum: TimeInterval = 15 * 60

    /// When the user left, while they're away.
    public private(set) var since: Date?
    private var asleep = false
    private var locked = false
    /// The last return, so idle time that still reaches back before it (no input since) can't
    /// start a time away that overlaps the one just reported.
    private var lastReturn: Date?

    public init() {}

    /// Away only for want of input, so a return shows up as input; worth checking often.
    public var isIdleAway: Bool { since != nil && !asleep && !locked }

    /// The time away when this event brings the user back after `minimum` or more.
    public mutating func handle(_ event: Event, at now: Date) -> DateInterval? {
        switch event {
        case .slept:
            asleep = true
            since = since ?? now
        case .locked:
            locked = true
            since = since ?? now
        case .woke:
            asleep = false
            return back(at: now)
        case .unlocked:
            locked = false
            return back(at: now)
        case .idle(let seconds):
            if seconds >= Self.minimum {
                let left = now.addingTimeInterval(-seconds)
                since = since ?? lastReturn.map { max(left, $0) } ?? left
            } else if since != nil {
                return back(at: now)
            }
        }
        return nil
    }

    private mutating func back(at now: Date) -> DateInterval? {
        guard !asleep, !locked, let left = since else { return nil }
        since = nil
        lastReturn = now
        guard now.timeIntervalSince(left) >= Self.minimum else { return nil }
        return DateInterval(start: left, end: now)
    }
}
