import CoreGraphics

/// The floating orb: where it may rest, which way it opens, and when a drag tears the shell
/// off its edge or docks it back.
public enum OrbGeometry {
    /// Gap kept between the orb and the edges of the visible frame.
    public static let margin: CGFloat = 8
    /// An orb released this close to an edge settles against it.
    public static let snapDistance: CGFloat = 24
    /// How far the pointer must travel before a press on the shell becomes a drag. An orb
    /// moves after a nudge; the notch needs a deliberate pull to come off its edge.
    public static let orbDragThreshold: CGFloat = 4
    public static let tearOffDistance: CGFloat = 40
    /// Half the width of the strip at the top centre where a dropped orb docks back.
    public static let dockHalfWidth: CGFloat = 120
    public static let dockDepth: CGFloat = 60
    /// Room left under the menu bar for an expanded system Dynamic Island.
    public static let systemIslandZone = CGSize(width: 360, height: 90)

    /// Where a new orb starts: the top right corner, below the menu bar.
    public static func defaultCentre(in visible: CGRect, size: CGFloat) -> CGPoint {
        CGPoint(x: visible.maxX - margin - size / 2 - 40, y: visible.maxY - margin - size / 2 - 40)
    }

    /// Keeps the orb inside the visible frame and, on a Mac with a system island, below it.
    public static func fitted(_ centre: CGPoint, in visible: CGRect, size: CGFloat, avoidsTopCentre: Bool = false)
        -> CGPoint
    {
        let half = size / 2 + margin
        var point = CGPoint(
            x: min(max(centre.x, visible.minX + half), visible.maxX - half),
            y: min(max(centre.y, visible.minY + half), visible.maxY - half))
        if avoidsTopCentre {
            let zone = islandZone(in: visible)
            if zone.insetBy(dx: -size / 2, dy: -size / 2).contains(point) {
                point.y = zone.minY - half
            }
        }
        return point
    }

    /// A released orb near an edge or corner settles flush against it.
    public static func snapped(_ centre: CGPoint, in visible: CGRect, size: CGFloat) -> CGPoint {
        let half = size / 2 + margin
        var point = centre
        if centre.x - half - visible.minX < snapDistance { point.x = visible.minX + half }
        if visible.maxX - (centre.x + half) < snapDistance { point.x = visible.maxX - half }
        if centre.y - half - visible.minY < snapDistance { point.y = visible.minY + half }
        if visible.maxY - (centre.y + half) < snapDistance { point.y = visible.maxY - half }
        return point
    }

    /// Which way the orb opens: down from the upper half and up from the lower half, lined
    /// up with the orb at the sides so the surface grows toward the middle of the screen.
    public static func anchor(for centre: CGPoint, in visible: CGRect) -> Placement {
        guard centre.y >= visible.midY else { return .bottom }
        let third = visible.width / 3
        if centre.x < visible.minX + third { return .topLeft }
        if centre.x > visible.maxX - third { return .topRight }
        return .top
    }

    /// Whether the pointer has moved far enough from where it went down to start a drag.
    public static func startsDrag(from start: CGPoint, to point: CGPoint, floating: Bool) -> Bool {
        hypot(point.x - start.x, point.y - start.y) >= (floating ? orbDragThreshold : tearOffDistance)
    }

    /// An orb dropped at the top centre goes back to its edge. Not on a Mac whose system
    /// island lives there.
    public static func docks(_ centre: CGPoint, in visible: CGRect, systemIsland: Bool) -> Bool {
        guard !systemIsland else { return false }
        return abs(centre.x - visible.midX) <= dockHalfWidth && centre.y >= visible.maxY - dockDepth
    }

    /// The strip under the menu bar an expanded system island can cover.
    static func islandZone(in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.midX - systemIslandZone.width / 2, y: visible.maxY - systemIslandZone.height,
            width: systemIslandZone.width, height: systemIslandZone.height)
    }

    /// "x,y", as positions are stored in UserDefaults.
    public static func encode(_ point: CGPoint) -> String { "\(Int(point.x.rounded())),\(Int(point.y.rounded()))" }

    public static func decode(_ text: String) -> CGPoint? {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }
}
