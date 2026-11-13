/// Tells a real screen lock from a fast user switch. macOS sends the same "screen is locked"
/// notification for both, so a lock only counts once it has held for `settle` while this
/// session stays in front and on the console.
public struct SessionLock: Equatable, Sendable {
    /// A lock notification arrived and no unlock since.
    public private(set) var screenLocked = false
    /// This login session is the one in front.
    public private(set) var sessionActive = true
    /// The lock held through the wait: a real lock that Wisp acts on.
    public private(set) var confirmed = false

    /// How long a lock must hold before it counts.
    public static let settle: Duration = .milliseconds(750)

    public enum Event: Sendable {
        case screenLocked
        case screenUnlocked
        case sessionResigned
        case sessionResumed
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Wait `settle`, then call `confirm(onConsole:)`.
        case confirmLater
        /// Cancel any wait; the screen is unlocked.
        case unlock
        /// Cancel any wait and hide everything: another session is in front.
        case suspend
        /// This session is back in front.
        case resume
    }

    public init() {}

    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .screenLocked:
            screenLocked = true
            return sessionActive ? .confirmLater : .none
        case .screenUnlocked:
            screenLocked = false
            confirmed = false
            return .unlock
        case .sessionResigned:
            sessionActive = false
            return .suspend
        case .sessionResumed:
            sessionActive = true
            return .resume
        }
    }

    /// After the wait: true the first time the lock still holds, in front and on the console.
    public mutating func confirm(onConsole: Bool) -> Bool {
        guard screenLocked, sessionActive, onConsole, !confirmed else { return false }
        confirmed = true
        return true
    }
}
