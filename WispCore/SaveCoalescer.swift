/// Turns a burst of changes into as few saves as possible: one save runs at a time, and
/// every change made while it runs is covered by a single save after it.
public struct SaveCoalescer: Sendable, Equatable {
    /// Changed since the last save began.
    public private(set) var dirty = false
    public private(set) var saving = false

    public init() {}

    /// Records a change. True when no save is running, so the caller should start one now.
    public mutating func changed() -> Bool {
        dirty = true
        return !saving
    }

    /// A save is about to take a snapshot. False when there's nothing new or one is running.
    public mutating func begin() -> Bool {
        guard dirty, !saving else { return false }
        dirty = false
        saving = true
        return true
    }

    /// The running save is done. True when changes came in meanwhile and need another save.
    public mutating func finish() -> Bool {
        saving = false
        return dirty
    }
}
