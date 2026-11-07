import CoreGraphics

/// Where a dragged island rests on a display, stored with the placement it was moved from so
/// that picking another placement (in Settings, the form menu or the ring) leaves it behind.
public struct IslandSpot: Equatable, Sendable {
    public let placement: Placement
    public let centre: CGPoint

    public init(placement: Placement, centre: CGPoint) {
        self.placement = placement
        self.centre = centre
    }

    /// "topRight@x,y", as spots are stored in UserDefaults.
    public var encoded: String { "\(placement.rawValue)@\(OrbGeometry.encode(centre))" }

    public init?(encoded text: String) {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let placement = Placement(rawValue: String(parts[0])),
            let centre = OrbGeometry.decode(String(parts[1]))
        else { return nil }
        self.init(placement: placement, centre: centre)
    }

    /// The centre for a display whose shell is now `current`; nil once it has another placement.
    public func centre(for current: Placement) -> CGPoint? {
        current == placement ? centre : nil
    }
}

/// When a press on an island may drag it. Corner and bottom islands sit over other apps'
/// windows, so a drag may only start where Wisp alone has the press: on the island's visible
/// shape while its panel takes clicks. Anywhere else the press also reaches the app
/// underneath, and dragging there must stay that app's.
public enum IslandDrag {
    /// The pointer is on a draggable island's visible shape (the closed island or the
    /// activity pill it shows), so its panel should take clicks there.
    public static func ownsPointer(at point: CGPoint, layout: NotchLayout, shape: CGRect) -> Bool {
        layout.movesAsIsland && shape.contains(point)
    }

    public static func mayStart(at press: CGPoint, layout: NotchLayout, shape: CGRect, panelTakesClicks: Bool) -> Bool {
        panelTakesClicks && ownsPointer(at: press, layout: layout, shape: shape)
    }
}

/// What letting go of a dragged island does.
public enum IslandDrop: Equatable, Sendable {
    /// Dropped back on its own spot: it goes home and forgets being moved.
    case restore
    /// It rests here, kept on screen, clear of a system island and flush with a near edge.
    case move(CGPoint)

    public static func outcome(
        dropped: CGPoint, in visible: CGRect, size: CGSize, systemIsland: Bool, home: CGPoint
    ) -> IslandDrop {
        let fitted = OrbGeometry.fitted(dropped, in: visible, size: size, avoidsTopCentre: systemIsland)
        let centre = OrbGeometry.snapped(fitted, in: visible, size: size)
        // Home may sit over the menu bar (a top island), where a drop can't reach; compare
        // with the nearest place a drop can land.
        let reachableHome = OrbGeometry.snapped(
            OrbGeometry.fitted(home, in: visible, size: size, avoidsTopCentre: systemIsland), in: visible, size: size)
        if hypot(centre.x - reachableHome.x, centre.y - reachableHome.y) <= OrbGeometry.snapDistance {
            return .restore
        }
        return .move(centre)
    }
}
