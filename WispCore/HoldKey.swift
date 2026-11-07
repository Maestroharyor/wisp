/// A key held with Hyper for push-to-talk, as the keyboard tap sees it: which events are
/// its own (and swallowed), and when the hold starts, ends or is cancelled.
public struct HoldKey: Sendable {
    public enum Event: Equatable, Sendable {
        case down
        case up
        case cancel
    }

    public enum Decision: Equatable, Sendable {
        /// Not the hold key's business: the tap carries on as usual.
        case notMine
        /// Swallow the event, and report a hold event if there is one.
        case swallow(Event?)
    }

    /// The hold key went down with Hyper and hasn't come up yet.
    public private(set) var holding = false
    /// Esc cancelled a hold; its key-up is swallowed too.
    private var escapeDown = false

    public init() {}

    /// One key event. `holdKey` nil means push-to-talk is off.
    public mutating func key(_ code: UInt16, down: Bool, hyperDown: Bool, holdKey: UInt16?) -> Decision {
        if code == KeyCodes.escape {
            if down, holding {
                escapeDown = true
                return .swallow(.cancel)
            }
            if !down, escapeDown {
                escapeDown = false
                return .swallow(nil)
            }
        }
        guard let holdKey, code == holdKey else { return .notMine }
        if down {
            // Key repeats while held are swallowed too, so nothing types.
            if holding { return .swallow(nil) }
            guard hyperDown else { return .notMine }
            holding = true
            return .swallow(.down)
        }
        // Released, even if Hyper came up first.
        guard holding else { return .notMine }
        holding = false
        return .swallow(.up)
    }

    /// The tap stopped or missed events: the key-up will never come, so a hold can't finish.
    public mutating func reset() -> Event? {
        escapeDown = false
        guard holding else { return nil }
        holding = false
        return .cancel
    }
}
