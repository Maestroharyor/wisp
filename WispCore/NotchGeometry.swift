import CoreGraphics

/// The parts of an `NSScreen` that notch layout depends on, in global AppKit
/// coordinates (origin at the bottom-left of the main screen).
public struct ScreenMetrics: Sendable, Equatable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    /// Visible menu bar area left of the camera housing; nil when the top edge is unobscured.
    public var auxiliaryTopLeft: CGRect?
    /// Visible menu bar area right of the camera housing; nil when the top edge is unobscured.
    public var auxiliaryTopRight: CGRect?

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeft: CGRect? = nil,
        auxiliaryTopRight: CGRect? = nil
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    /// Zero when the menu bar is hidden (auto-hide or full screen).
    public var menuBarHeight: CGFloat { max(frame.maxY - visibleFrame.maxY, 0) }

    public var hasCameraHousing: Bool {
        auxiliaryTopLeft != nil && auxiliaryTopRight != nil && safeAreaTop > 0
    }
}

/// How the shelf is drawn on a display.
public enum NotchStyle: Sendable, Equatable {
    /// Black shape attached to the top edge that grows out of it (real or drawn notch).
    case notch
    /// Floating capsule just below the top edge.
    case island
}

/// The screen edge the shell attaches to and grows out of.
public enum ScreenEdge: Sendable, Equatable {
    case top
    case bottom
    case left
    case right

    /// Left and right: the shell slides out sideways.
    public var isSide: Bool { self == .left || self == .right }
}

/// Where the shell sits on a display. `top` uses the camera housing or a drawn notch;
/// `left` and `right` attach a notch on its side; the corners and `bottom` float an island.
public enum Placement: String, CaseIterable, Sendable, Identifiable {
    case top
    case topLeft
    case topRight
    case bottom
    case left
    case right

    public var id: Self { self }

    public var edge: ScreenEdge {
        switch self {
        case .top, .topLeft, .topRight: .top
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        }
    }

    /// The two-finger swipe that opens the shelf: away from the edge, the way it grows.
    public var openingSwipe: Swipe {
        switch edge {
        case .top: .down
        case .bottom: .up
        case .left: .right
        case .right: .left
        }
    }
}

/// Tunable sizes, in points.
public struct NotchSizes: Sendable, Equatable {
    /// Drawn notch on displays without a camera housing. Height follows the menu bar.
    public var drawnNotchWidth: CGFloat = 150
    public var drawnNotchFallbackHeight: CGFloat = 24
    public var island = CGSize(width: 130, height: 32)
    public var islandTopMargin: CGFloat = 4
    /// Gap between an island and the menu bar, Dock or screen edge it rests against.
    public var edgeMargin: CGFloat = 6
    /// How far a top-corner island sits from the side of the screen.
    public var cornerInset: CGFloat = 12
    /// The resting tab on a left or right edge, flush with it like a notch on its side.
    public var sideTab = CGSize(width: 10, height: 76)
    public var peekGrowth = CGSize(width: 16, height: 10)
    /// The largest surface any content may ask for; the panel is sized to fit it.
    public var maxSurface = CGSize(width: 900, height: 560)
    /// Room around the surface for its shadow.
    public var shadowPadding: CGFloat = 30
    /// Extra margin when hit-testing a small shape, so it is easy to reach.
    public var hoverTolerance: CGFloat = 6

    public init() {}

    public static let standard = NotchSizes()
}

/// Every rectangle the notch needs on one display, in global AppKit coordinates.
public struct NotchLayout: Sendable, Equatable {
    public let style: NotchStyle
    public let placement: Placement
    /// The resting shape: the camera housing, a drawn notch, the idle island or a side tab.
    public let closedRect: CGRect
    public let screenFrame: CGRect
    /// The fixed panel: big enough for the largest surface plus shadow, flush with the edge.
    public fileprivate(set) var panelFrame: CGRect = .zero
    public let peekGrowth: CGSize
    public let hoverTolerance: CGFloat
    /// Height of a one-line pill. Equal to the closed shape except on side edges, whose
    /// resting tab is tall and thin.
    public let barHeight: CGFloat
    /// The line hit regions reach out to: the screen edge, or the menu bar or Dock in front of it.
    public let edgeLine: CGFloat

    public var edge: ScreenEdge { placement.edge }

    public var peekRect: CGRect { peekRect(strength: 1) }

    /// The hover peek with its growth scaled (the hover strength setting).
    public func peekRect(strength: CGFloat) -> CGRect {
        let scale = min(max(strength, 0), 2)
        return surfaceRect(
            size: CGSize(
                width: closedRect.width + peekGrowth.width * scale,
                height: closedRect.height + peekGrowth.height * scale
            )
        )
    }

    /// A surface of `size` growing out of the closed shape, away from its edge, and kept
    /// on screen. Top and bottom surfaces are centred on the shape (top corners line up
    /// with it instead); side surfaces are centred vertically.
    public func surfaceRect(size: CGSize) -> CGRect {
        let width = min(size.width, screenFrame.width)
        let height = min(size.height, screenFrame.height)
        let closed = closedRect
        let origin: CGPoint
        switch placement {
        case .top: origin = CGPoint(x: closed.midX - width / 2, y: closed.maxY - height)
        case .topLeft: origin = CGPoint(x: closed.minX, y: closed.maxY - height)
        case .topRight: origin = CGPoint(x: closed.maxX - width, y: closed.maxY - height)
        case .bottom: origin = CGPoint(x: closed.midX - width / 2, y: closed.minY)
        case .left: origin = CGPoint(x: closed.minX, y: closed.midY - height / 2)
        case .right: origin = CGPoint(x: closed.maxX - width, y: closed.midY - height / 2)
        }
        var rect = CGRect(origin: origin, size: CGSize(width: width, height: height))
        rect.origin.x = min(max(rect.minX, screenFrame.minX), screenFrame.maxX - width)
        rect.origin.y = min(max(rect.minY, screenFrame.minY), screenFrame.maxY - height)
        return rect
    }

    /// The closed shape widened by `wing` on each side, for a compact live activity.
    /// It is never shorter than the closed shape.
    public func compactRect(wing: CGFloat, height: CGFloat) -> CGRect {
        surfaceRect(
            size: CGSize(width: closedRect.width + wing * 2, height: max(height, closedRect.height))
        )
    }

    /// The area where the pointer counts as inside a shape: a margin around it, with the
    /// side facing the edge running exactly to the edge line. Flicking to the edge always
    /// hits, and a Dock or menu bar beyond that line is never covered.
    public func hitRegion(for shape: CGRect) -> CGRect {
        let region = shape.insetBy(dx: -hoverTolerance, dy: -hoverTolerance)
        var minX = region.minX
        var maxX = region.maxX
        var minY = region.minY
        var maxY = region.maxY
        switch edge {
        case .top: maxY = edgeLine
        case .bottom: minY = edgeLine
        case .left: minX = edgeLine
        case .right: maxX = edgeLine
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public enum NotchGeometry {
    public static func layout(
        for screen: ScreenMetrics,
        prefersIsland: Bool = false,
        placement: Placement = .top,
        sizes: NotchSizes = .standard
    ) -> NotchLayout {
        let visible = screen.visibleFrame
        let style: NotchStyle
        let closed: CGRect
        let edgeLine: CGFloat

        switch placement {
        case .top:
            style = screen.hasCameraHousing || !prefersIsland ? .notch : .island
            closed = topClosedRect(for: screen, style: style, sizes: sizes)
            edgeLine = screen.frame.maxY
        case .topLeft, .topRight:
            // Under the menu bar, so the app and status menus stay reachable.
            style = .island
            edgeLine = visible.maxY
            let x =
                placement == .topLeft
                ? visible.minX + sizes.cornerInset : visible.maxX - sizes.cornerInset - sizes.island.width
            closed = CGRect(
                origin: CGPoint(x: x, y: edgeLine - sizes.edgeMargin - sizes.island.height), size: sizes.island)
        case .bottom:
            // Above the Dock when it shares the edge.
            style = .island
            edgeLine = visible.minY
            closed = CGRect(
                origin: CGPoint(x: screen.frame.midX - sizes.island.width / 2, y: edgeLine + sizes.edgeMargin),
                size: sizes.island)
        case .left, .right:
            style = .island
            edgeLine = placement == .left ? visible.minX : visible.maxX
            let x = placement == .left ? edgeLine : edgeLine - sizes.sideTab.width
            closed = CGRect(origin: CGPoint(x: x, y: visible.midY - sizes.sideTab.height / 2), size: sizes.sideTab)
        }

        let side = placement.edge.isSide
        var layout = NotchLayout(
            style: style,
            placement: placement,
            closedRect: closed,
            screenFrame: screen.frame,
            // Side tabs swell outward more than they grow taller.
            peekGrowth: side
                ? CGSize(width: sizes.peekGrowth.height, height: sizes.peekGrowth.width) : sizes.peekGrowth,
            hoverTolerance: sizes.hoverTolerance,
            barHeight: side ? sizes.island.height : closed.height,
            edgeLine: edgeLine
        )
        layout.panelFrame = panelFrame(for: layout, sizes: sizes)
        return layout
    }

    private static func topClosedRect(for screen: ScreenMetrics, style: NotchStyle, sizes: NotchSizes) -> CGRect {
        if let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight, screen.safeAreaTop > 0 {
            return CGRect(
                x: left.maxX,
                y: screen.frame.maxY - screen.safeAreaTop,
                width: right.minX - left.maxX,
                height: screen.safeAreaTop
            )
        }
        if style == .island {
            let top = screen.frame.maxY - sizes.islandTopMargin
            return CGRect(
                x: screen.frame.midX - sizes.island.width / 2,
                y: top - sizes.island.height,
                width: sizes.island.width,
                height: sizes.island.height
            )
        }
        let height = screen.menuBarHeight > 0 ? screen.menuBarHeight : sizes.drawnNotchFallbackHeight
        return CGRect(
            x: screen.frame.midX - sizes.drawnNotchWidth / 2,
            y: screen.frame.maxY - height,
            width: sizes.drawnNotchWidth,
            height: height
        )
    }

    /// The largest surface plus room for its shadow, stretched to the screen edge it grows
    /// from and kept on its own screen.
    private static func panelFrame(for layout: NotchLayout, sizes: NotchSizes) -> CGRect {
        let screen = layout.screenFrame
        var panel = layout.surfaceRect(size: sizes.maxSurface).union(layout.closedRect)
            .insetBy(dx: -sizes.shadowPadding, dy: -sizes.shadowPadding)
        switch layout.edge {
        case .top: panel.size.height = screen.maxY - panel.minY
        case .bottom:
            panel.size.height = panel.maxY - screen.minY
            panel.origin.y = screen.minY
        case .left:
            panel.size.width = panel.maxX - screen.minX
            panel.origin.x = screen.minX
        case .right: panel.size.width = screen.maxX - panel.minX
        }
        return panel.intersection(screen)
    }
}
