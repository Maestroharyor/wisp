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

/// Tunable sizes, in points.
public struct NotchSizes: Sendable, Equatable {
    /// Drawn notch on displays without a camera housing. Height follows the menu bar.
    public var drawnNotchWidth: CGFloat = 150
    public var drawnNotchFallbackHeight: CGFloat = 24
    public var island = CGSize(width: 130, height: 32)
    public var islandTopMargin: CGFloat = 4
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
    /// The resting shape: the camera housing, a drawn notch, or the idle island.
    public let closedRect: CGRect
    public let screenFrame: CGRect
    /// The fixed panel: big enough for the largest surface plus shadow, top-aligned to the screen.
    public let panelFrame: CGRect
    public let peekGrowth: CGSize
    public let hoverTolerance: CGFloat

    /// Top edge every surface hangs from.
    public var top: CGFloat { closedRect.maxY }

    public var peekRect: CGRect {
        surfaceRect(
            size: CGSize(
                width: closedRect.width + peekGrowth.width,
                height: closedRect.height + peekGrowth.height
            )
        )
    }

    /// A surface of `size`, hanging from the top edge and centred on the notch,
    /// kept inside the screen horizontally.
    public func surfaceRect(size: CGSize) -> CGRect {
        let width = min(size.width, screenFrame.width)
        var rect = CGRect(x: closedRect.midX - width / 2, y: top - size.height, width: width, height: size.height)
        rect.origin.x = min(max(rect.minX, screenFrame.minX), screenFrame.maxX - width)
        return rect
    }

    /// The closed shape widened by `wing` on each side, for a compact live activity.
    /// It is never shorter than the closed shape.
    public func compactRect(wing: CGFloat, height: CGFloat) -> CGRect {
        surfaceRect(
            size: CGSize(width: closedRect.width + wing * 2, height: max(height, closedRect.height))
        )
    }

    /// The area where the pointer counts as inside a shape. Small shapes get a margin
    /// that also reaches up to the screen edge, so flicking to the top always hits.
    public func hitRegion(for shape: CGRect) -> CGRect {
        var region = shape.insetBy(dx: -hoverTolerance, dy: -hoverTolerance)
        region.size.height = max(region.height, screenFrame.maxY - region.minY)
        return region
    }
}

public enum NotchGeometry {
    public static func layout(
        for screen: ScreenMetrics,
        prefersIsland: Bool = false,
        sizes: NotchSizes = .standard
    ) -> NotchLayout {
        let style: NotchStyle = screen.hasCameraHousing || !prefersIsland ? .notch : .island
        let closed: CGRect

        if let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight, screen.safeAreaTop > 0 {
            closed = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - screen.safeAreaTop,
                width: right.minX - left.maxX,
                height: screen.safeAreaTop
            )
        } else if style == .island {
            let top = screen.frame.maxY - sizes.islandTopMargin
            closed = CGRect(
                x: screen.frame.midX - sizes.island.width / 2,
                y: top - sizes.island.height,
                width: sizes.island.width,
                height: sizes.island.height
            )
        } else {
            let height = screen.menuBarHeight > 0 ? screen.menuBarHeight : sizes.drawnNotchFallbackHeight
            closed = CGRect(
                x: screen.frame.midX - sizes.drawnNotchWidth / 2,
                y: screen.frame.maxY - height,
                width: sizes.drawnNotchWidth,
                height: height
            )
        }

        let width = min(sizes.maxSurface.width + sizes.shadowPadding * 2, screen.frame.width)
        let height = min(
            screen.frame.maxY - closed.maxY + sizes.maxSurface.height + sizes.shadowPadding, screen.frame.height)
        var panel = CGRect(x: closed.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        // Keep the panel on its own screen even if the notch sits off-centre.
        panel.origin.x = min(max(panel.minX, screen.frame.minX), screen.frame.maxX - panel.width)

        return NotchLayout(
            style: style,
            closedRect: closed,
            screenFrame: screen.frame,
            panelFrame: panel,
            peekGrowth: sizes.peekGrowth,
            hoverTolerance: sizes.hoverTolerance
        )
    }
}
