import CoreGraphics

/// Where Wisp's own hover label goes. The notch panel never activates Wisp, so system
/// tooltips don't show there; this places a small label next to the hovered control instead,
/// kept inside the surface that would otherwise clip it.
public enum HoverHint {
    /// How long the pointer rests on a control before its label shows.
    public static let delay: Duration = .milliseconds(500)
    /// Space between the control and its label.
    public static let gap: CGFloat = 4
    /// How close the label may come to the container's edges.
    public static let inset: CGFloat = 6

    public enum Edge: Sendable, Equatable {
        case top, bottom
    }

    public struct Placement: Sendable, Equatable {
        public let edge: Edge
        /// The label's centre, in the same space as the anchor and bounds (y down).
        public let center: CGPoint
    }

    /// Places a label of `label` size beside `anchor` within `bounds` (all y down). Keeps the
    /// preferred edge when the label fits there, flips when only the other edge fits, and takes
    /// the roomier edge when neither does. Horizontally the label centres on the anchor and is
    /// slid back inside the bounds.
    public static func placement(preferred: Edge, anchor: CGRect, label: CGSize, bounds: CGRect) -> Placement {
        let needed = label.height + gap
        let room: (Edge) -> CGFloat = { edge in
            switch edge {
            case .top: anchor.minY - bounds.minY - inset
            case .bottom: bounds.maxY - inset - anchor.maxY
            }
        }
        let other: Edge = preferred == .top ? .bottom : .top
        let edge: Edge
        if room(preferred) >= needed {
            edge = preferred
        } else if room(other) >= needed {
            edge = other
        } else {
            edge = room(preferred) >= room(other) ? preferred : other
        }

        let y: CGFloat
        switch edge {
        case .top: y = anchor.minY - gap - label.height / 2
        case .bottom: y = anchor.maxY + gap + label.height / 2
        }

        let half = label.width / 2
        let lowest = bounds.minX + inset + half
        let highest = bounds.maxX - inset - half
        let x = highest < lowest ? lowest : min(max(anchor.midX, lowest), highest)
        return Placement(edge: edge, center: CGPoint(x: x, y: y))
    }
}
