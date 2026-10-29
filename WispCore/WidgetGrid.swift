import CoreGraphics

/// The Widgets page: an icon grid of every switched-on widget, filled column by column
/// (top to bottom, then left to right) in one or two rows.
public enum WidgetGrid {
    public static let tileSize: CGFloat = 44
    public static let cellWidth: CGFloat = 72
    /// Tile, a gap and one line of caption.
    public static let cellHeight: CGFloat = 61
    public static let columnSpacing: CGFloat = 8
    public static let rowSpacing: CGFloat = 0

    public static func clampedRows(_ rows: Int) -> Int { min(max(rows, 1), 2) }

    public static func columns(count: Int, rows: Int) -> Int {
        guard count > 0 else { return 0 }
        let rows = clampedRows(rows)
        return (count + rows - 1) / rows
    }

    public static func contentWidth(count: Int, rows: Int) -> CGFloat {
        let columns = columns(count: count, rows: rows)
        guard columns > 0 else { return 0 }
        return CGFloat(columns) * cellWidth + CGFloat(columns - 1) * columnSpacing
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
