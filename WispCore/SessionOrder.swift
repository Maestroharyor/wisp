import Foundation

/// The order of the Agents widget's session lists: what needs you first, then what you pinned,
/// then running, ready and done sessions, newest first in each. Hidden sessions and projects,
/// and done sessions past their keep time, are left out.
public enum SessionOrder {
    /// How long a done session stays in the lists.
    public enum KeepDone: String, CaseIterable, Sendable {
        case fiveMinutes
        case oneHour
        case untilDismissed

        public var interval: TimeInterval? {
            switch self {
            case .fiveMinutes: 5 * 60
            case .oneHour: 60 * 60
            case .untilDismissed: nil
            }
        }
    }

    /// What the user pinned and hid, from Preferences. Projects go by name, as the rows show them.
    public struct Rules: Equatable, Sendable {
        public var pinnedSessions: Set<String> = []
        public var pinnedProjects: Set<String> = []
        /// Each hidden session and when it was hidden; it comes back once its state changes.
        public var hiddenSessions: [String: Date] = [:]
        public var hiddenProjects: Set<String> = []
        public var keepDone: KeepDone = .untilDismissed

        public init() {}

        public func isPinned(_ session: AgentSession) -> Bool {
            pinnedSessions.contains(session.id) || pinnedProjects.contains(session.project)
        }

        func isHidden(_ session: AgentSession) -> Bool {
            if hiddenProjects.contains(session.project) { return true }
            guard let hidden = hiddenSessions[session.id] else { return false }
            return (session.stateSince ?? session.updated) <= hidden
        }
    }

    /// Hidden sessions kept in Preferences; older ones are forgotten.
    public static let hiddenLimit = 50

    public static func arrange(_ sessions: [AgentSession], rules: Rules, now: Date) -> [AgentSession] {
        sessions.filter { session in
            guard !rules.isHidden(session) else { return false }
            guard session.state == .finished, !rules.isPinned(session), let keep = rules.keepDone.interval else {
                return true
            }
            return now.timeIntervalSince(session.stateSince ?? session.updated) < keep
        }
        .sorted { lhs, rhs in
            let (left, right) = (rank(lhs, rules: rules), rank(rhs, rules: rules))
            if left != right { return left < right }
            if lhs.updated != rhs.updated { return lhs.updated > rhs.updated }
            return lhs.id < rhs.id
        }
    }

    /// `hidden` with `id` added at `date`, keeping the newest `hiddenLimit`.
    public static func hiding(_ id: String, at date: Date, in hidden: [String: Date]) -> [String: Date] {
        var result = hidden
        result[id] = date
        guard result.count > hiddenLimit else { return result }
        let kept = result.sorted { $0.value > $1.value }.prefix(hiddenLimit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private static func rank(_ session: AgentSession, rules: Rules) -> Int {
        if session.state == .needsApproval || session.state == .waiting { return 0 }
        if rules.isPinned(session) { return 1 }
        switch session.state {
        case .running: return 2
        case .idle: return 3
        case .finished, .needsApproval, .waiting: return 4
        }
    }
}
