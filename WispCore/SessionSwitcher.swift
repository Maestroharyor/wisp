import Foundation

/// The session switcher's selection (Hyper+G, or ⌃⌥⌘G): Up and Down move through the live
/// sessions, wrapping at the ends, and Return jumps to the selected one. The selection follows a
/// session id, so it stays on the same session when the list reorders under it.
public struct SessionSwitcher: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case up
        case down
        case jump
    }

    public static let up: UInt16 = 126
    public static let down: UInt16 = 125
    public static let returnKey: UInt16 = 36
    public static let enter: UInt16 = 76

    private var chosen: String?

    public init() {}

    /// What a key does while the switcher shows; nil leaves it alone.
    public static func key(_ keyCode: UInt16) -> Key? {
        switch keyCode {
        case up: .up
        case down: .down
        case returnKey, enter: .jump
        default: nil
        }
    }

    /// Back to the first session, for a switcher that just opened.
    public mutating func reset() {
        chosen = nil
    }

    /// The selected session: the chosen one while it's still listed, otherwise the first.
    public func selected(in ids: [String]) -> String? {
        if let chosen, ids.contains(chosen) { return chosen }
        return ids.first
    }

    public mutating func select(_ id: String) {
        chosen = id
    }

    /// Moves by `step` rows, wrapping around.
    public mutating func move(_ step: Int, in ids: [String]) {
        guard !ids.isEmpty else { return }
        let current = selected(in: ids).flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = ((current + step) % ids.count + ids.count) % ids.count
        chosen = ids[next]
    }

    /// One short line for a session's row.
    public static func status(_ session: AgentSession) -> String {
        if session.compacting { return "Compacting" }
        switch session.state {
        case .needsApproval: return "Needs approval"
        case .waiting: return "Needs your input"
        case .running: return "Working"
        case .idle: return "Ready"
        case .finished: return "Done"
        }
    }
}
