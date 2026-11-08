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

    /// The hold key went down with Hyper and the hold hasn't ended yet.
    public private(set) var holding = false
    /// Esc cancelled a hold; its repeats and key-up are swallowed too.
    private var escapeDown = false
    /// A hold ended (Esc or a reset) while its key may still be down: the key's repeats and
    /// release are swallowed so nothing types, and none of them start a new hold.
    private var abandoned = false

    public init() {}

    /// One key event. `holdKey` nil means push-to-talk is off. `isRepeat` marks a key-down sent
    /// because the key is held.
    public mutating func key(
        _ code: UInt16, down: Bool, hyperDown: Bool, holdKey: UInt16?, isRepeat: Bool = false
    ) -> Decision {
        if code == KeyCodes.escape {
            if down, escapeDown { return .swallow(nil) }
            if down, holding, !isRepeat {
                escapeDown = true
                abandon()
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
            // Only a fresh press starts a hold. A repeat here means the key was held before Hyper,
            // or the hold was abandoned; starting then would record again without a new press.
            if isRepeat { return abandoned ? .swallow(nil) : .notMine }
            abandoned = false
            guard hyperDown else { return .notMine }
            holding = true
            return .swallow(.down)
        }
        if abandoned {
            abandoned = false
            return .swallow(nil)
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
        abandon()
        return .cancel
    }

    private mutating func abandon() {
        holding = false
        abandoned = true
    }
}
