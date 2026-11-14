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
    /// A card under the notch (a notification, an approval); `extra` adds rows below it,
    /// such as the reply bar or a question's options. `wide` gives an approval's diff more room.
    case notification(extra: CGFloat, wide: Bool = false)
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
    public static let navPillSize = CGSize(width: 216, height: 34)
    public static let navPillGap: CGFloat = 12
    public static let notificationWidth: CGFloat = 480
    /// An approval card showing a diff, so its lines and gutter aren't cut short.
    public static let wideNotificationWidth: CGFloat = 520
    public static let mediaPageWidth: CGFloat = 420
    public static let notificationCardHeight: CGFloat = 84
    public static let replyBarHeight: CGFloat = 48
    /// The row of answers under a question from an agent.
    public static let questionRowHeight: CGFloat = 40
    /// One answer chip, and the space between chips across and down.
    public static let questionChipHeight: CGFloat = 28
    public static let questionChipSpacing: CGFloat = 6
    /// Rows of answers the card grows to; more scroll.
    public static let questionMaxRows = 3

    /// How many rows answer chips of these widths wrap onto in `width`, filling each row in
    /// order. A chip wider than the row gets a row of its own.
    public static func questionRows(options: [CGFloat], width: CGFloat) -> Int {
        max(flowRows(options, width: width, spacing: questionChipSpacing).count, 1)
    }

    /// Items of these widths laid out left to right and wrapped to `width`: the indices on each
    /// row. An item wider than the row gets a row of its own.
    public static func flowRows(_ widths: [CGFloat], width: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var used: CGFloat = 0
        for (index, item) in widths.enumerated() {
            if let last = rows.indices.last, used + spacing + item <= width {
                rows[last].append(index)
                used += spacing + item
            } else {
                rows.append([index])
                used = item
            }
        }
        return rows
    }

    /// The answers' height for `rows` of chips, at most `questionMaxRows`.
    public static func questionRowHeight(rows: Int) -> CGFloat {
        let shown = CGFloat(min(max(rows, 1), questionMaxRows) - 1)
        return questionRowHeight + shown * (questionChipHeight + questionChipSpacing)
    }
    /// An approval card opened to show its diff, command or plan, with a reason row.
    public static let approvalPreviewHeight: CGFloat = 220
    /// One row of an approval card's inline diff, and the space between rows.
    public static let inlineDiffRowHeight: CGFloat = 14
    public static let inlineDiffRowSpacing: CGFloat = 1
    /// Around the inline diff's rows: their box's padding, the counts line under it and the gap
    /// above the card's buttons.
    public static let inlineDiffChrome: CGFloat = 30
    /// Allow All, Always allow and Terminal: the quieter row above Deny and Allow.
    public static let approvalQuietRowHeight: CGFloat = 26
    /// Deny and Allow as two full-width buttons, with the card's bottom margin.
    public static let approvalActionRowHeight: CGFloat = 40

    /// The inline diff's height for `rows` rows (at most `InlineDiff.maxLines`); none for none.
    public static func inlineDiffHeight(rows: Int) -> CGFloat {
        let shown = CGFloat(min(max(rows, 0), InlineDiff.maxLines))
        guard shown > 0 else { return 0 }
        return shown * inlineDiffRowHeight + (shown - 1) * inlineDiffRowSpacing + inlineDiffChrome
    }

    /// What a tool or plan approval card adds under the standard card: the open preview or
    /// else the inline diff, then the quiet row and Deny and Allow.
    public static func approvalCardExtra(previewOpen: Bool, inlineDiffRows: Int) -> CGFloat {
        let above = previewOpen ? approvalPreviewHeight : inlineDiffHeight(rows: inlineDiffRows)
        return above + approvalQuietRowHeight + approvalActionRowHeight
    }
    /// The answer under an AI result card's title; longer answers scroll.
    public static let aiResultHeight: CGFloat = 132

    /// `contentScale` zooms the open shelf's content (the shelf size setting); pills and
    /// cards keep their size. `extraHeight` is how far the user dragged the shelf taller, in
    /// points on screen; it's clamped to what the screen allows (see `ShelfHeight`).
    public static func rect(
        for spec: SurfaceSpec, in layout: NotchLayout, sizes: NotchSizes = .standard, contentScale: CGFloat = 1,
        peekStrength: CGFloat = 1, extraHeight: CGFloat = 0
    ) -> CGRect {
        let base = baseRect(
            for: spec, in: layout, sizes: sizes, contentScale: contentScale, peekStrength: peekStrength)
        let extra = shelfExtra(for: spec, base: base, in: layout, requested: extraHeight)
        guard extra > 0 else { return base }
        return layout.surfaceRect(size: CGSize(width: base.width, height: base.height + extra))
    }

    /// The part of `requested` the shelf actually grows by: none for pills and cards, or where
    /// the handle isn't offered, and never past the screen's limit.
    public static func shelfExtra(
        for spec: SurfaceSpec, in layout: NotchLayout, sizes: NotchSizes = .standard, contentScale: CGFloat = 1,
        requested: CGFloat
    ) -> CGFloat {
        guard requested > 0 else { return 0 }
        let base = baseRect(for: spec, in: layout, sizes: sizes, contentScale: contentScale)
        return shelfExtra(for: spec, base: base, in: layout, requested: requested)
    }

    private static func shelfExtra(for spec: SurfaceSpec, base: CGRect, in layout: NotchLayout, requested: CGFloat)
        -> CGFloat
    {
        guard requested > 0, shelfContentWidth(for: spec, in: layout) != nil else { return 0 }
        return min(requested, ShelfHeight.maxExtra(base: base, in: layout))
    }

    private static func baseRect(
        for spec: SurfaceSpec, in layout: NotchLayout, sizes: NotchSizes, contentScale: CGFloat,
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
        case .notification(let extra, let wide):
            let height = bar + notificationCardHeight + extra
            return layout.surfaceRect(
                size: CGSize(width: wide ? wideNotificationWidth : notificationWidth, height: height))
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

    /// Space between the main pill and a bubble beside it. A notch's flare reaches past the
    /// pill along its edge, so the bubble clears the flare too; a thinner gap leaves a sliver
    /// of menu bar between them that reads as a stray line.
    public static func bubbleGap(flare: CGFloat) -> CGFloat { max(6, flare + 4) }

    /// Round bubbles for extra live activities, as tall as the pill. Centred pills get one
    /// on each side (the first on the right unless `firstOnLeft`); corner pills put both on
    /// the inward side; side-edge pills stack them below and above, against the edge.
    /// `flare` is the closed shell's flare along its edge, 0 for an island.
    public static func bubbleRects(
        beside pill: CGRect, count: Int, firstOnLeft: Bool = false, placement: Placement = .top, flare: CGFloat = 0
    ) -> [CGRect] {
        // As thick as the pill: its height on the top and bottom, its width on the sides.
        let size = placement.edge.isSide ? pill.width : pill.height
        let bubbleGap = bubbleGap(flare: flare)
        let step = size + bubbleGap
        func bubble(x: CGFloat, y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: size, height: size) }
        let rects: [CGRect]
        switch placement {
        case .top, .bottom, .floating:
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

    /// The trailing button of a horizontal pill (the watch pill's stop), only where it's
    /// drawn: not in the upright side pill or the minimal pill, which show a glyph and a dot.
    public static func pillButtonZone(in pill: CGRect, placement: Placement, minimal: Bool) -> CGRect? {
        guard !placement.edge.isSide, !minimal else { return nil }
        let width = min(meetingMuteWidth, pill.width)
        return CGRect(x: pill.maxX - width, y: pill.minY, width: width, height: pill.height)
    }

    public static let cardCloseZoneSize = CGSize(width: 52, height: 40)

    /// Where a click closes a card: its top trailing corner, under the notch (`topInset`),
    /// where the close button shows while the pointer is on the card.
    public static func cardCloseZone(in card: CGRect, topInset: CGFloat) -> CGRect {
        CGRect(
            x: card.maxX - cardCloseZoneSize.width, y: card.maxY - topInset - cardCloseZoneSize.height,
            width: cardCloseZoneSize.width, height: cardCloseZoneSize.height)
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
