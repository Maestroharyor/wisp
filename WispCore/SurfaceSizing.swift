import CoreGraphics

/// What the notch surface is currently showing, reduced to what decides its size.
public enum SurfaceSpec: Sendable, Equatable {
    case closed
    case peek
    case compact(wide: Bool)
    case medium
    /// Home: the widgets' total width (see `HomeLayout.contentWidth`).
    case home(contentWidth: CGFloat, editing: Bool)
    /// The Widgets page: an icon grid of the switched-on widgets.
    case widgetGrid(count: Int, rows: Int)
    /// The Widgets page with one widget opened on its own.
    /// One widget on its own. Wide ones (Agents, Calendar) get room for a detail page.
    case widgetSolo(wide: Bool)
    /// The Media page: a large player.
    case media
    case tray(items: Int)
    /// Drop tiles: the four built-in ones plus up to two Drop Actions.
    case dropTiles(extra: Int)
    /// A notification card under the notch; `replying` adds the reply bar.
    case notification(replying: Bool)
}

/// Turns a `SurfaceSpec` into a rectangle on a display, using the shell metrics.
public enum SurfaceSizing {
    public static let pickerRowHeight: CGFloat = 76
    public static let multiCardWidth: CGFloat = 243
    public static let trayItemWidth: CGFloat = 84
    /// A solo widget with a detail page: a list beside the selected item's details.
    public static let wideSoloWidth: CGFloat = 560
    /// Wide enough for the tray's summary and its labelled action buttons on one row.
    public static let trayMinimumContentWidth: CGFloat = 5 * trayItemWidth
    public static let tileSize: CGFloat = 96
    public static let tileSpacing: CGFloat = 10
    public static let maxDropActionTiles = 2
    public static let navPillSize = CGSize(width: 174, height: 34)
    public static let navPillGap: CGFloat = 12
    public static let notificationWidth: CGFloat = 480
    public static let mediaPageWidth: CGFloat = 420
    public static let notificationCardHeight: CGFloat = 84
    public static let replyBarHeight: CGFloat = 48

    /// `contentScale` zooms the open shelf's content (the shelf size setting); pills and
    /// cards keep their size.
    public static func rect(
        for spec: SurfaceSpec, in layout: NotchLayout, sizes: NotchSizes = .standard, contentScale: CGFloat = 1,
        peekStrength: CGFloat = 1
    ) -> CGRect {
        func shelf(contentWidth: CGFloat, contentHeight: CGFloat, _ layout: NotchLayout, _ sizes: NotchSizes)
            -> CGRect
        {
            let scale = shelfScale(contentWidth: contentWidth, requested: contentScale, layout: layout, sizes: sizes)
            return Self.shelf(
                contentWidth: contentWidth * scale, contentHeight: contentHeight * scale, layout, sizes)
        }
        let notchStyle = layout.style == .notch
        let closed = layout.closedRect
        let bar = layout.barHeight

        switch spec {
        case .closed:
            return closed
        case .peek:
            return layout.peekRect(strength: peekStrength)
        case .compact(let wide):
            if layout.edge.isSide {
                return layout.surfaceRect(
                    size: wide ? ActivityMetrics.interactiveSidePillSize : ActivityMetrics.sidePillSize)
            }
            if notchStyle {
                let wing = wide ? ActivityMetrics.interactiveNotchWing : ActivityMetrics.compactNotchWing
                return layout.compactRect(wing: wing, height: bar)
            }
            let width = wide ? ActivityMetrics.interactiveIslandWidth : ActivityMetrics.compactIslandWidth
            return layout.surfaceRect(size: CGSize(width: max(width, closed.width), height: bar))
        case .medium:
            let wide = rect(for: .compact(wide: true), in: layout, sizes: sizes).width
            let size = CGSize(
                width: max(wide, 360),
                height: bar + ActivityMetrics.cardContentHeight + 12
            )
            return layout.surfaceRect(size: size)
        case .home(_, let editing):
            let extra = editing ? pickerRowHeight : 0
            return shelf(
                contentWidth: shelfContentWidth(for: spec, in: layout) ?? 0,
                contentHeight: shelfContentHeight + extra, layout, sizes)
        case .widgetGrid, .widgetSolo, .media, .tray, .dropTiles:
            return shelf(
                contentWidth: shelfContentWidth(for: spec, in: layout) ?? 0, contentHeight: shelfContentHeight,
                layout, sizes)
        case .notification(let replying):
            let height = bar + notificationCardHeight + (replying ? replyBarHeight : 0)
            return layout.surfaceRect(size: CGSize(width: notificationWidth, height: height))
        }
    }

    /// The width a shelf page's content asks for; nil for pills and cards.
    public static func shelfContentWidth(for spec: SurfaceSpec, in layout: NotchLayout) -> CGFloat? {
        switch spec {
        case .home(let contentWidth, _):
            return contentWidth
        case .widgetGrid(let count, let rows):
            return WidgetGrid.contentWidth(count: count, rows: rows)
        case .widgetSolo(let wide):
            return wide ? wideSoloWidth : ShellMetrics.soloCardWidth(notchStyle: layout.style == .notch)
        case .media:
            return mediaPageWidth
        case .tray(let items):
            // One more card than files: the "drop more" card always sits last.
            return max(CGFloat(items + 1) * trayItemWidth, trayMinimumContentWidth)
        case .dropTiles(let extra):
            let count = CGFloat(4 + min(max(extra, 0), maxDropActionTiles))
            return count * tileSize + (count - 1) * tileSpacing
        case .closed, .peek, .compact, .medium, .notification:
            return nil
        }
    }

    /// Content height shared by every shelf page, so switching tabs never changes
    /// the shelf's height. Tall enough for the media player.
    public static let shelfContentHeight: CGFloat = ShellMetrics.mediaWidgetContentHeight

    /// Space between the main pill and a bubble beside it.
    public static let bubbleGap: CGFloat = 6

    /// Round bubbles for extra live activities, as tall as the pill. Centred pills get one
    /// on each side (the first on the right unless `firstOnLeft`); corner pills put both on
    /// the inward side; side-edge pills stack them below and above, against the edge.
    public static func bubbleRects(
        beside pill: CGRect, count: Int, firstOnLeft: Bool = false, placement: Placement = .top
    ) -> [CGRect] {
        // As thick as the pill: its height on the top and bottom, its width on the sides.
        let size = placement.edge.isSide ? pill.width : pill.height
        let step = size + bubbleGap
        func bubble(x: CGFloat, y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: size, height: size) }
        let rects: [CGRect]
        switch placement {
        case .top, .bottom:
            let right = bubble(x: pill.maxX + bubbleGap, y: pill.minY)
            let left = bubble(x: pill.minX - step, y: pill.minY)
            rects = firstOnLeft ? [left, right] : [right, left]
        case .topLeft:
            rects = [
                bubble(x: pill.maxX + bubbleGap, y: pill.minY), bubble(x: pill.maxX + bubbleGap + step, y: pill.minY),
            ]
        case .topRight:
            rects = [bubble(x: pill.minX - step, y: pill.minY), bubble(x: pill.minX - step * 2, y: pill.minY)]
        case .left, .right:
            let x = placement == .left ? pill.minX : pill.maxX - size
            let below = bubble(x: x, y: pill.minY - step)
            let above = bubble(x: x, y: pill.maxY + bubbleGap)
            rects = firstOnLeft ? [above, below] : [below, above]
        }
        return Array(rects.prefix(max(count, 0)))
    }

    /// Width of the meeting pill's mute button at the trailing end of a horizontal pill.
    public static let meetingMuteWidth: CGFloat = 56

    /// The part of the meeting pill that mutes the microphone: its trailing end, or on a
    /// side edge the upper half where the mic glyph sits (AppKit y runs up).
    public static func meetingMuteZone(in pill: CGRect, placement: Placement) -> CGRect {
        if placement.edge.isSide {
            return CGRect(x: pill.minX, y: pill.midY, width: pill.width, height: pill.height / 2)
        }
        let width = min(meetingMuteWidth, pill.width)
        return CGRect(x: pill.maxX - width, y: pill.minY, width: width, height: pill.height)
    }

    /// The floating Home/Tray/Clipboard pill, centred on an open surface on the side away
    /// from the edge: above it on the bottom edge, below it everywhere else.
    public static func navPillRect(for surface: CGRect, placement: Placement = .top) -> CGRect {
        let y =
            placement == .bottom
            ? surface.maxY + navPillGap : surface.minY - navPillGap - navPillSize.height
        return CGRect(
            x: surface.midX - navPillSize.width / 2,
            y: y,
            width: navPillSize.width,
            height: navPillSize.height
        )
    }

    /// The zoom a shelf page actually gets. Growing stops where the shelf reaches its
    /// widest, so a roomy shelf never squeezes a wide Home; shrinking always applies.
    public static func shelfScale(
        contentWidth: CGFloat, requested: CGFloat, layout: NotchLayout, sizes: NotchSizes = .standard
    ) -> CGFloat {
        let scale = min(max(requested, 0.5), 2)
        guard scale > 1, contentWidth > 0 else { return scale }
        let insets = ShellMetrics.shelfInsets(notchStyle: layout.style == .notch, notchHeight: layout.barHeight)
        let room = sizes.maxSurface.width - insets.leading - insets.trailing
        return max(1, min(scale, room / contentWidth))
    }

    private static func shelf(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        _ layout: NotchLayout,
        _ sizes: NotchSizes
    ) -> CGRect {
        let notchStyle = layout.style == .notch
        let insets = ShellMetrics.shelfInsets(notchStyle: notchStyle, notchHeight: layout.barHeight)
        let width = min(
            max(
                insets.leading + contentWidth + insets.trailing, ShellMetrics.shelfMinimumWidth(notchStyle: notchStyle)),
            sizes.maxSurface.width
        )
        let height = min(insets.top + contentHeight + insets.bottom, sizes.maxSurface.height)
        return layout.surfaceRect(size: CGSize(width: width, height: height))
    }
}
