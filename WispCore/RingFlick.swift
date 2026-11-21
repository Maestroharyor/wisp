import CoreGraphics
import Foundation

/// A flick: press the ring's button, throw the pointer towards a segment and let go. Moving
/// past a small dead zone makes it a pick even when it's quick, and overshooting the ring
/// still picks the segment in that direction; a throw far past the ring is a change of mind.
public enum RingFlick {
    public static let deadZone: CGFloat = 14
    public static let cancelBeyond: CGFloat = 380

    /// `start` is where the press began and `centre` the ring's centre, which differ when the
    /// ring was moved to stay on screen. Landing on the ring always picks what's there; only a
    /// throw from inside the ring out past its edge, in the direction it went, is an overshoot.
    public static func release(
        after held: TimeInterval, from start: CGPoint, to end: CGPoint, centre: CGPoint, hit: RingHit, slots: Int,
        expanded: Int? = nil, subItems: Int = 0
    ) -> RingGesture.Outcome {
        guard distance(start, end) >= deadZone else { return RingGesture.release(after: held, on: hit) }
        switch hit {
        case .slot, .sub: return .pick(hit)
        case .centre: return RingGesture.release(after: held, on: hit)
        case .none: break
        }
        let out = distance(centre, end)
        guard slots > 0, distance(centre, start) < RingGeometry.ringOuter,
            out > distance(centre, start) + deadZone, agrees(from: start, to: end, centre: centre)
        else { return RingGesture.release(after: held, on: hit) }
        if out > cancelBeyond { return .close }
        let angle = RingGeometry.normalised(atan2(end.x - centre.x, end.y - centre.y) * 180 / .pi)
        if let expanded, let item = subItem(at: angle, parent: expanded, slots: slots, count: subItems) {
            return .pick(.sub(item))
        }
        return .pick(.slot(slot(at: angle, slots: slots)))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    /// The throw points the way the pointer ends up from the centre, within 60 degrees.
    private static func agrees(from start: CGPoint, to end: CGPoint, centre: CGPoint) -> Bool {
        let move = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let radial = CGVector(dx: end.x - centre.x, dy: end.y - centre.y)
        let lengths = hypot(move.dx, move.dy) * hypot(radial.dx, radial.dy)
        guard lengths > 0 else { return false }
        return (move.dx * radial.dx + move.dy * radial.dy) / lengths >= cos(.pi / 3)
    }

    static func slot(at angle: CGFloat, slots: Int) -> Int {
        let step = 360 / CGFloat(slots)
        return Int((angle / step).rounded()) % slots
    }

    /// The open sub-ring's item in that direction, if the throw went through its fan.
    static func subItem(at angle: CGFloat, parent: Int, slots: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let parentAngle = RingGeometry.slotAngle(parent, count: slots)
        return (0..<count).first { index in
            let centre = RingGeometry.subAngle(index, count: count, around: parentAngle)
            return abs(RingGeometry.difference(angle, centre)) <= RingGeometry.subStep / 2
        }
    }
}

public enum RingKey: Sendable {
    case left
    case right
    case up
    case down
}

/// Where the keyboard is on the ring: the highlighted segment or sub-ring item, and which
/// sub-ring is open.
public struct RingCursor: Equatable, Sendable {
    public var hover: RingHit
    public var expanded: Int?

    public init(hover: RingHit, expanded: Int?) {
        self.hover = hover
        self.expanded = expanded
    }
}

/// The arrow keys on an open ring: left and right step round it (clockwise is right), up
/// opens the highlighted segment's sub-ring and down comes back out of it.
public enum RingKeys {
    public static func move(
        _ key: RingKey, from cursor: RingCursor, slots: Int, subItems: (Int) -> Int
    ) -> RingCursor {
        guard slots > 0 else { return cursor }
        switch cursor.hover {
        case .slot(let index):
            switch key {
            case .right: return RingCursor(hover: .slot((index + 1) % slots), expanded: nil)
            case .left: return RingCursor(hover: .slot((index + slots - 1) % slots), expanded: nil)
            case .up:
                guard subItems(index) > 0 else { return RingCursor(hover: cursor.hover, expanded: nil) }
                return RingCursor(hover: .sub(0), expanded: index)
            case .down: return RingCursor(hover: cursor.hover, expanded: nil)
            }
        case .sub(let item):
            guard let parent = cursor.expanded else { return RingCursor(hover: .slot(0), expanded: nil) }
            let last = max(subItems(parent) - 1, 0)
            switch key {
            case .right: return RingCursor(hover: .sub(min(item + 1, last)), expanded: parent)
            case .left: return RingCursor(hover: .sub(max(item - 1, 0)), expanded: parent)
            case .up: return cursor
            case .down: return RingCursor(hover: .slot(parent), expanded: nil)
            }
        case .centre, .none:
            switch key {
            case .right, .up: return RingCursor(hover: .slot(0), expanded: nil)
            case .left: return RingCursor(hover: .slot(slots - 1), expanded: nil)
            case .down: return cursor
            }
        }
    }
}

/// What a key does on the open ring.
public enum RingCommand: Equatable, Sendable {
    case close
    case clearQuery
    case submit
    case move(RingKey)
    case moveResult(Int)
    case pickSlot(Int)
    /// The search becomes this text.
    case type(String)
    case ignore
}

/// Keys on the open ring. With nothing typed, digits pick segments and arrows move round the
/// ring; typing starts a search, after which arrows move through its results.
public enum RingTyping {
    public static let returnKey: UInt16 = 36
    public static let keypadEnter: UInt16 = 76
    public static let delete: UInt16 = 51
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126
    public static let zero: UInt16 = 29
    public static let maxQuery = 40

    public static func command(keyCode: UInt16, characters: String, modified: Bool, query: String) -> RingCommand {
        let searching = !query.isEmpty
        switch keyCode {
        case KeyCodes.escape: return searching ? .clearQuery : .close
        case returnKey, keypadEnter: return .submit
        case delete:
            guard searching else { return .ignore }
            let shorter = String(query.dropLast())
            return shorter.isEmpty ? .clearQuery : .type(shorter)
        case left: return searching ? .ignore : .move(.left)
        case right: return searching ? .ignore : .move(.right)
        case up: return searching ? .moveResult(-1) : .move(.up)
        case down: return searching ? .moveResult(1) : .move(.down)
        default: break
        }
        guard !modified else { return .ignore }
        if !searching, let digit = KeyCodes.digit(forKeyCode: keyCode) { return .pickSlot(digit - 1) }
        // 0 is the tenth, as on a keyboard's number row.
        if !searching, keyCode == zero { return .pickSlot(9) }
        // Function and navigation keys send characters from a private range; they aren't text.
        guard !characters.isEmpty, !KeyCodes.isFunctionKey(keyCode),
            characters.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
            })
        else { return .ignore }
        // A search can't start with a space.
        if !searching, characters.allSatisfy(\.isWhitespace) { return .ignore }
        guard query.count + characters.count <= maxQuery else { return .ignore }
        return .type(query + characters)
    }
}
