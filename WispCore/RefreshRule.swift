import Foundation

/// When a cached read is worth repeating: never read, older than `maxAge`, or marked dirty
/// (a change notice arrived). Pages rebuild on every switch, so their stores ask this
/// instead of reading again each time they appear.
public struct RefreshRule: Equatable, Sendable {
    public let maxAge: TimeInterval

    public init(maxAge: TimeInterval) {
        self.maxAge = maxAge
    }

    public func isDue(lastRefresh: Date?, now: Date, dirty: Bool = false) -> Bool {
        guard let lastRefresh, !dirty else { return true }
        let age = now.timeIntervalSince(lastRefresh)
        // A negative age means the clock moved back, so the read's age is unknown.
        return age < 0 || age >= maxAge
    }

    /// The week of events; EKEventStoreChanged marks it dirty sooner.
    public static let calendar = RefreshRule(maxAge: 300)
    /// The list of the user's Shortcuts.
    public static let shortcuts = RefreshRule(maxAge: 300)
    /// Each agent's hook file. Wisp's own installs and removals refresh straight away.
    public static let agentHooks = RefreshRule(maxAge: 30)
}
