import Foundation

/// Keeps one copy of Wisp running. Two copies draw two notches, so bubbles show twice.
public enum InstanceGuard {
    public struct Instance: Equatable, Sendable {
        public let pid: Int32
        /// Nil when macOS doesn't know, as for a copy started outside Launch Services.
        public let launched: Date?

        public init(pid: Int32, launched: Date?) {
            self.pid = pid
            self.launched = launched
        }
    }

    /// Whether `me` should hand over and quit. The oldest copy stays; an unknown launch time
    /// counts as oldest, and a tie goes to the lower process id, so two copies launched
    /// together never both quit.
    public static func yields(_ me: Instance, to others: [Instance]) -> Bool {
        let mine = (me.launched ?? .distantPast, me.pid)
        return others.contains { other in
            other.pid != me.pid && (other.launched ?? .distantPast, other.pid) < mine
        }
    }
}
