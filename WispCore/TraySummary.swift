import Foundation

/// Text for the tray header and file cards.
public enum TraySummary {
    /// Decimal units, as Finder shows them. Whole numbers from 10 up, one decimal below.
    public static func bytes(_ count: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(max(0, count))
        var unit = 0
        while value >= 1_000, unit < units.count - 1 {
            value /= 1_000
            unit += 1
        }
        if unit == 0 || value >= 10 || value == value.rounded() {
            return "\(Int(value.rounded())) \(units[unit])"
        }
        return String(format: "%.1f %@", value, units[unit])
    }

    /// "2 files · 3.4 MB", or "1 selected · 1.2 MB" while files are selected.
    /// `count` covers files whose size could not be read.
    public static func header(sizes: [Int64], selectedSizes: [Int64], count: Int? = nil) -> String {
        let total = count ?? sizes.count
        let label: String
        let bytesShown: [Int64]
        if selectedSizes.isEmpty {
            label = total == 1 ? "1 file" : "\(total) files"
            bytesShown = sizes
        } else {
            label = "\(selectedSizes.count) selected"
            bytesShown = selectedSizes
        }
        guard !bytesShown.isEmpty else { return label }
        return "\(label) · \(bytes(bytesShown.reduce(0, +)))"
    }

    /// "PNG · 1.2 MB" under a file card.
    public static func detail(pathExtension: String, size: Int64?) -> String {
        let kind = pathExtension.isEmpty ? "File" : pathExtension.uppercased()
        guard let size else { return kind }
        return "\(kind) · \(bytes(size))"
    }
}
