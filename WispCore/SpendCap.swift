import Foundation

/// "Pause at $X per session": when a session's spend crosses the cap, Wisp asks Keep going,
/// Raise or Stop, and holds that session's next request until the user chooses. Works from the
/// spend Wisp already tracks: Claude Code's own figure when its status line reports one, an
/// estimate from the transcript otherwise (Codex is always estimated).
public struct SpendCap: Equatable, Sendable {
    public struct Crossing: Equatable, Sendable {
        /// The limit the session reached.
        public let limit: Double
        /// What Raise takes it to: one more cap's worth.
        public let raise: Double
    }

    /// Limits raised past the cap, per session.
    private var raised: [String: Double] = [:]
    /// Sessions told to keep going: never asked again.
    private var unlimited: Set<String> = []
    /// Sessions waiting for a choice.
    private var held: Set<String> = []
    /// Sessions stopped at the cap, not asked again until their next prompt.
    private var stopped: Set<String> = []

    public init() {}

    /// The crossing to ask about now, once per limit. `cap` nil means the setting is off.
    public mutating func check(session id: String, cost: Double?, cap: Double?) -> Crossing? {
        guard let cap, cap > 0, let cost, !unlimited.contains(id), !held.contains(id), !stopped.contains(id)
        else { return nil }
        let limit = raised[id] ?? cap
        guard cost >= limit else { return nil }
        held.insert(id)
        return Crossing(limit: limit, raise: limit + cap)
    }

    public func isHeld(_ id: String) -> Bool { held.contains(id) }

    public mutating func keepGoing(_ id: String) {
        held.remove(id)
        unlimited.insert(id)
    }

    /// The cap was turned off while the session waited: it goes on, and a cap turned on again
    /// still covers it.
    public mutating func release(_ id: String) {
        held.remove(id)
    }

    public mutating func raise(_ id: String, to limit: Double) {
        held.remove(id)
        raised[id] = limit
    }

    public mutating func stop(_ id: String) {
        held.remove(id)
        stopped.insert(id)
    }

    /// The user prompted again after Stop, so the cap watches the session again.
    public mutating func newTurn(_ id: String) {
        stopped.remove(id)
    }

    public mutating func forget(_ id: String) {
        raised[id] = nil
        unlimited.remove(id)
        held.remove(id)
        stopped.remove(id)
    }

    /// "Session reached $5", or "about $5" for an estimate.
    public static func title(limit: Double, estimated: Bool) -> String {
        "Session reached \(estimated ? "about " : "")\(SpendBudget.amount(limit))"
    }

    public static func raiseTitle(_ limit: Double) -> String { "Raise to \(SpendBudget.amount(limit))" }
}
