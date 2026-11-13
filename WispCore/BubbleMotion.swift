/// Split progress for the two bubbles beside the pill: 0 tucked inside it, 1 at rest beside
/// it. `first` is the bubble on the right, unless Settings put it on the left.
public struct BubbleSides: Equatable, Sendable {
    public var first: Double
    public var second: Double

    public init(first: Double, second: Double) {
        self.first = first
        self.second = second
    }

    public static let tucked = BubbleSides(first: 0, second: 0)

    /// One side out per live bubble, at most two.
    public static func target(count: Int) -> BubbleSides {
        BubbleSides(first: count > 0 ? 1 : 0, second: count > 1 ? 1 : 0)
    }

    public subscript(index: Int) -> Double { index == 0 ? first : second }

    public var total: Double { first + second }
}

/// What each bubble side draws while bubbles come, go and swap. Results always have two
/// entries, one per side; nil means the side has nothing to draw. A short `shown` reads as
/// nothing on the missing sides.
public enum BubbleMotion {
    /// A side that will show a different activity than it does now. It merges back in first,
    /// then splits out again with its new glyph.
    public static func swapped<ID: Equatable>(shown: [ID?], live: [ID]) -> Bool {
        (0..<min(live.count, 2)).contains { index in
            side(index, of: shown).map { $0 != live[index] } ?? false
        }
    }

    /// Live bubbles take their side; a side with none keeps its last glyph while it merges away.
    public static func showing<T>(shown: [T?], live: [T]) -> [T?] {
        (0..<2).map { index in index < live.count ? live[index] : side(index, of: shown) }
    }

    /// Once the motion has settled: a side tucked away with no live bubble draws nothing, so
    /// no empty circle is left to show next time it moves.
    public static func settled<T>(shown: [T?], live: [T], split: BubbleSides) -> [T?] {
        (0..<2).map { index in
            if index < live.count { return live[index] }
            return split[index] > 0 ? side(index, of: shown) : nil
        }
    }

    private static func side<T>(_ index: Int, of shown: [T?]) -> T? {
        shown.indices.contains(index) ? shown[index] : nil
    }
}
