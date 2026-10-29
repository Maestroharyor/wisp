import CoreGraphics

/// The Widgets page: an icon grid of every switched-on widget, filled column by column
/// (top to bottom, then left to right) in one or two rows.
public enum WidgetGrid {
    /// Sizes for one row count: a single row gets big tiles, two rows trade tile size
    /// for a clear gap between a caption and the tile below it.
    public struct Metrics: Equatable, Sendable {
        public let tileSize: CGFloat
        public let captionGap: CGFloat
        public let captionSize: CGFloat
        /// Tile, gap and one line of caption.
        public let cellHeight: CGFloat
        public let rowSpacing: CGFloat
    }

    public static let cellWidth: CGFloat = 76
    public static let minColumnSpacing: CGFloat = 8
    /// Wider than this and a short row stops reading as one group.
    public static let maxColumnSpacing: CGFloat = 28
    /// Up to this many widgets always sit in one row.
    public static let singleRowLimit = 5

    public static func metrics(rows: Int) -> Metrics {
        clampedRows(rows) == 1
            ? Metrics(tileSize: 54, captionGap: 7, captionSize: 11, cellHeight: 76, rowSpacing: 0)
            : Metrics(tileSize: 40, captionGap: 4, captionSize: 10, cellHeight: 56, rowSpacing: 10)
    }

    public static func clampedRows(_ rows: Int) -> Int { min(max(rows, 1), 2) }

    /// The rows actually used: a few widgets fill one row instead of huddling in two.
    public static func rows(count: Int, preferred: Int) -> Int {
        count <= singleRowLimit ? 1 : clampedRows(preferred)
    }

    /// Column spacing that spreads the columns across `available`, between the base and the cap.
    public static func spreadSpacing(columns: Int, available: CGFloat) -> CGFloat {
        guard columns > 1 else { return minColumnSpacing }
        let spread = (available - CGFloat(columns) * cellWidth) / CGFloat(columns - 1)
        return min(max(spread, minColumnSpacing), maxColumnSpacing)
    }

    public static func columns(count: Int, rows: Int) -> Int {
        guard count > 0 else { return 0 }
        let rows = clampedRows(rows)
        return (count + rows - 1) / rows
    }

    public static func contentWidth(count: Int, rows: Int) -> CGFloat {
        let columns = columns(count: count, rows: rows)
        guard columns > 0 else { return 0 }
        return CGFloat(columns) * cellWidth + CGFloat(columns - 1) * minColumnSpacing
    }

    /// Moves `item` to just before `target`; an unknown target moves it to the end.
    public static func move(_ order: [String], item: String, before target: String) -> [String] {
        guard item != target, order.contains(item) else { return order }
        var result = order.filter { $0 != item }
        let index = result.firstIndex(of: target) ?? result.endIndex
        result.insert(item, at: index)
        return result
    }

    /// The saved grid order restricted to enabled widgets, with newly enabled ones
    /// appended in their enabled order.
    public static func merge(order: [String], enabled: [String]) -> [String] {
        var result: [String] = []
        for id in order + enabled where enabled.contains(id) && !result.contains(id) {
            result.append(id)
        }
        return result
    }
}
