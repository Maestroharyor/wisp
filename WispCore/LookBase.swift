import Foundation

/// The look a profile replaces, so the next profile without a look can put it back. An edit
/// by hand becomes the new base, so a later switch never throws it away.
public struct LookBase: Equatable, Sendable {
    /// The user's own look while a profile's look is on; saved so a relaunch keeps it.
    public private(set) var base: Appearance?

    public init(base: Appearance? = nil) {
        self.base = base
    }

    /// A profile puts on `look`. Returns what to show; the user's custom sounds stay.
    public mutating func putOn(_ look: Appearance, over current: Appearance) -> Appearance {
        if base == nil { base = current }
        return look.keepingSounds(of: current)
    }

    /// A profile without a look: the user's own look, if a profile had replaced it.
    public mutating func takeOff() -> Appearance? {
        defer { base = nil }
        return base
    }

    public mutating func editedByHand() {
        base = nil
    }
}
