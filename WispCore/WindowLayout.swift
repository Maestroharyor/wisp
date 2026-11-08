import Foundation

/// Layout rules for the widget pages in the shelf window: how many card columns fit, when a
/// list gets an inspector or preview column beside it, and the readable width of text pages.
public enum WindowLayout {
    /// Space around a page's content.
    public static let margin: Double = 20
    /// Space between cards.
    public static let spacing: Double = 16
    /// The narrowest a card gets before a column is dropped.
    public static let cardMinimum: Double = 220
    /// List and text pages stop growing here, so lines stay easy to read.
    public static let readableCap: Double = 760
    /// The inspector or preview column's width.
    public static let inspectorWidth: Double = 300
    /// The narrowest detail that still has room for a list and an inspector.
    public static let inspectorThreshold: Double = 680

    /// Card columns at least `minimum` wide (with `spacing` between) that fit in `width`,
    /// from 1 to `maximum`.
    public static func columns(
        width: Double, minimum: Double = cardMinimum, spacing: Double = spacing, maximum: Int = 4
    ) -> Int {
        guard width > 0, minimum > 0 else { return 1 }
        let fit = Int(((width + spacing) / (minimum + spacing)).rounded(.down))
        return min(max(fit, 1), max(maximum, 1))
    }

    /// Whether a detail `width` wide shows the inspector or preview column.
    public static func showsInspector(width: Double, threshold: Double = inspectorThreshold) -> Bool {
        width >= threshold
    }

    /// The content width of a capped page in a detail `available` wide, inside its margins.
    public static func readableWidth(available: Double) -> Double {
        max(min(available - 2 * margin, readableCap), 0)
    }
}
