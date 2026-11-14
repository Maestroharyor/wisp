import CoreGraphics

/// The extra height the user drags the open shelf to with the handle on its bottom edge.
public enum ShelfHeight {
    /// The shelf's bottom may come at most this far down the screen under the menu bar. Past
    /// about 60% it covers most of the front window, and the shelf stops reading as a drop-down.
    public static let maxScreenFraction: CGFloat = 0.6
    /// On large displays the shelf stops here: that's room for a long session list, and the
    /// panel (sized to the tallest shelf) stays a sensible size.
    public static let heightCap: CGFloat = 760
    /// A drag that ends closer than this to the usual height goes back to it, so a nudge
    /// doesn't leave the shelf a few points off.
    public static let snapDistance: CGFloat = 16

    /// Only a shelf hanging from the top edge gets the handle: its bottom edge is free to move.
    /// Bottom and side shelves grow toward the middle (a handle there would pull the wrong
    /// way), and the orb or a moved island opens toward wherever there's room.
    public static func offered(in layout: NotchLayout) -> Bool {
        layout.edge == .top && !layout.floatsFree
    }

    /// The tallest the shelf may be on the layout's screen: down to `maxScreenFraction` of the
    /// visible height, never so low that the nav pill under it leaves the visible screen, and
    /// no taller than `heightCap`.
    public static func maxHeight(in layout: NotchLayout) -> CGFloat {
        let visible = layout.visibleFrame
        let top = layout.closedRect.maxY
        let byFraction = visible.maxY - visible.height * maxScreenFraction
        let byNavPill = visible.minY + SurfaceSizing.navPillGap + SurfaceSizing.navPillSize.height + 6
        return min(max(top - max(byFraction, byNavPill), 0), heightCap)
    }

    /// How much taller than `base` (the shelf at its usual height) it may grow.
    public static func maxExtra(base: CGRect, in layout: NotchLayout) -> CGFloat {
        guard offered(in: layout) else { return 0 }
        return max(maxHeight(in: layout) - base.height, 0)
    }

    /// The extra height during a drag that began at `start` and has moved `translation`
    /// points down (negative is up).
    public static func dragged(from start: CGFloat, by translation: CGFloat, maxExtra: CGFloat) -> CGFloat {
        min(max(start + translation, 0), max(maxExtra, 0))
    }

    /// Where a drag comes to rest: whole points, or the usual height when it ended close to it.
    public static func settled(_ extra: CGFloat) -> CGFloat {
        extra < snapDistance ? 0 : extra.rounded()
    }

    /// The stored extra for a page; nothing for a page without the handle or a bad value.
    public static func extra(for key: String?, in stored: [String: Double]) -> CGFloat {
        guard let key, let value = stored[key], value.isFinite, value > 0 else { return 0 }
        return CGFloat(value)
    }

    /// `stored` with the page's extra set. The usual height is left out rather than stored as 0.
    public static func storing(_ extra: CGFloat, for key: String, in stored: [String: Double]) -> [String: Double] {
        var result = stored
        result[key] = extra > 0 ? Double(extra) : nil
        return result
    }
}
