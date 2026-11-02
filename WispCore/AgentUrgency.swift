import Foundation

/// Which session the notch pill shows when several are going: a moment that just happened
/// first (Needs you before Done, since it asks for something), then work in progress, then a pending approval (its card has its
/// own slot, so the pill stays as it was). Ties go to the session that sent a hook last.
public enum AgentUrgency {
    /// How long Done or Needs you outranks work, matching how long the pill shows it.
    public static let moment: TimeInterval = 4

    public static func pick(_ sessions: [AgentSession], now: Date) -> (primary: AgentSession?, others: Int) {
        let ranked = sessions.map { (session: $0, rank: rank($0, now: now)) }.filter { $0.rank > 0 }
        let primary = ranked.max { a, b in
            a.rank != b.rank ? a.rank < b.rank : recency(a.session) < recency(b.session)
        }?.session
        let others = sessions.filter { $0.id != primary?.id && isLive($0) }.count
        return (primary, others)
    }

    /// When the current Done or Needs you stops outranking work, so the pill can be picked
    /// again then; nil when there's no such moment.
    public static func momentEnds(_ sessions: [AgentSession], now: Date) -> Date? {
        sessions.filter { isMoment($0, now: now) }.map { since($0) + moment }.max()
    }

    private static func rank(_ session: AgentSession, now: Date) -> Int {
        if isMoment(session, now: now) { return session.state == .waiting ? 4 : 3 }
        switch session.state {
        case .running: return 2
        case .idle: return session.compacting ? 2 : 0
        case .needsApproval: return 1
        case .waiting, .finished: return 0
        }
    }

    private static func isMoment(_ session: AgentSession, now: Date) -> Bool {
        (session.state == .finished || session.state == .waiting) && now.timeIntervalSince(since(session)) < moment
    }

    private static func isLive(_ session: AgentSession) -> Bool {
        [.running, .waiting, .needsApproval].contains(session.state) || session.compacting
    }

    private static func recency(_ session: AgentSession) -> Date { session.latestActivity }

    /// When the current moment began: the change of state, or a later reminder.
    private static func since(_ session: AgentSession) -> Date {
        let changed = session.stateSince ?? session.updated
        return max(changed, session.nudged ?? changed)
    }
}
