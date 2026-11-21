/// ← and → between the open shelf's pages, as the nav pill orders them.
public enum PageKeys {
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124

    public static func step(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case left: -1
        case right: 1
        default: nil
        }
    }

    /// The page after `step` from `index`, stopping at the first and last rather than wrapping,
    /// as Apple's tab views do.
    public static func next(from index: Int, step: Int, count: Int) -> Int {
        min(max(index + step, 0), max(count - 1, 0))
    }
}
