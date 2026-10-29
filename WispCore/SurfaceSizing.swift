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
    case widgetSolo
    /// The Media page: a large player.
    case media
    case tray(items: Int)
    case dropTiles
    /// A notification card under the notch; `replying` adds the reply bar.
    case notification(replying: Bool)
}

/// Turns a `SurfaceSpec` into a rectangle on a display, using the measured shell metrics.
public enum SurfaceSizing {
    public static let pickerRowHeight: CGFloat = 76
    public static let multiCardWidth: CGFloat = 243
    public static let trayItemWidth: CGFloat = 84
    public static let tileSize: CGFloat = 96
    public static let tileSpacing: CGFloat = 10
    public static let navPillSize = CGSize(width: 174, height: 34)
    public static let navPillGap: CGFloat = 12
    public static let notificationWidth: CGFloat = 480
    public static let mediaPageWidth: CGFloat = 420
    public static let notificationCardHeight: CGFloat = 84
    public static let replyBarHeight: CGFloat = 48

    public static func rect(for spec: SurfaceSpec, in layout: NotchLayout, sizes: NotchSizes = .standard) -> CGRect {
        let notchStyle = layout.style == .notch
        let closed = layout.closedRect

        switch spec {
        case .closed:
            return closed
        case .peek:
            return layout.peekRect
        case .compact(let wide):
            if notchStyle {
                let wing = wide ? ActivityMetrics.interactiveNotchWing : ActivityMetrics.compactNotchWing
                return layout.compactRect(wing: wing, height: closed.height)
            }
            let width = wide ? ActivityMetrics.interactiveIslandWidth : ActivityMetrics.compactIslandWidth
            return layout.surfaceRect(size: CGSize(width: max(width, closed.width), height: closed.height))
        case .medium:
            let wide = rect(for: .compact(wide: true), in: layout, sizes: sizes).width
            let size = CGSize(
                width: max(wide, 360),
                height: closed.height + ActivityMetrics.cardContentHeight + 12
            )
            return layout.surfaceRect(size: size)
        case .home(let contentWidth, let editing):
            let extra = editing ? pickerRowHeight : 0
            return shelf(contentWidth: contentWidth, contentHeight: shelfContentHeight + extra, layout, sizes)
        case .widgetGrid(let count, let rows):
            let content = WidgetGrid.contentWidth(count: count, rows: rows)
            return shelf(contentWidth: content, contentHeight: shelfContentHeight, layout, sizes)
        case .widgetSolo:
            let content = ShellMetrics.soloCardWidth(notchStyle: notchStyle)
            return shelf(contentWidth: content, contentHeight: shelfContentHeight, layout, sizes)
        case .media:
            return shelf(contentWidth: mediaPageWidth, contentHeight: shelfContentHeight, layout, sizes)
        case .tray(let items):
            let content = CGFloat(max(items, 4)) * trayItemWidth
            return shelf(contentWidth: content, contentHeight: shelfContentHeight, layout, sizes)
        case .notification(let replying):
            let height = closed.height + notificationCardHeight + (replying ? replyBarHeight : 0)
            return layout.surfaceRect(size: CGSize(width: notificationWidth, height: height))
        case .dropTiles:
            let content = 4 * tileSize + 3 * tileSpacing
            return shelf(contentWidth: content, contentHeight: shelfContentHeight, layout, sizes)
        }
    }

    /// Scale the open content starts from so it grows out of the notch together with
    /// the surface (one spring drives both): the closed width relative to the open width.
    public static func revealScale(from closed: CGRect, to open: CGRect) -> CGFloat {
        guard open.width > 0 else { return 1 }
        return min(max(closed.width / open.width, 0.25), 1)
    }

    /// Content height shared by every shelf page, so switching tabs never changes
    /// the shelf's height. Tall enough for the media player.
    public static let shelfContentHeight: CGFloat = ShellMetrics.mediaWidgetContentHeight

    /// The floating Home/Tray/Clipboard pill centred under an open surface.
    public static func navPillRect(below surface: CGRect) -> CGRect {
        CGRect(
            x: surface.midX - navPillSize.width / 2,
            y: surface.minY - navPillGap - navPillSize.height,
            width: navPillSize.width,
            height: navPillSize.height
        )
    }

    private static func shelf(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        _ layout: NotchLayout,
        _ sizes: NotchSizes
    ) -> CGRect {
        let notchStyle = layout.style == .notch
        let insets = ShellMetrics.shelfInsets(notchStyle: notchStyle, notchHeight: layout.closedRect.height)
        let width = min(
            max(
                insets.leading + contentWidth + insets.trailing, ShellMetrics.shelfMinimumWidth(notchStyle: notchStyle)),
            sizes.maxSurface.width
        )
        let height = min(insets.top + contentHeight + insets.bottom, sizes.maxSurface.height)
        return layout.surfaceRect(size: CGSize(width: width, height: height))
    }
}
