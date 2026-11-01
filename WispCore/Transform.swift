import CoreGraphics
import Foundation

/// Detects a quick side-to-side shake while dragging: several horizontal direction
/// reversals, each covering real distance, within a short window.
public struct ShakeDetector: Sendable {
    public var minimumReversals = 3
    public var minimumTravel: CGFloat = 25
    public var window: TimeInterval = 0.7

    private var anchorX: CGFloat?
    private var direction: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var fired = false

    public init() {}

    /// Returns true once, on the sample that completes a shake.
    public mutating func add(_ point: CGPoint, at time: TimeInterval) -> Bool {
        guard !fired else { return false }
        guard let anchor = anchorX else {
            anchorX = point.x
            return false
        }
        let delta = point.x - anchor
        guard abs(delta) >= minimumTravel else { return false }
        let newDirection: CGFloat = delta > 0 ? 1 : -1
        if direction != 0, newDirection != direction { reversals.append(time) }
        direction = newDirection
        anchorX = point.x
        reversals.removeAll { time - $0 > window }
        if reversals.count >= minimumReversals {
            fired = true
            return true
        }
        return false
    }

    public mutating func reset() {
        anchorX = nil
        direction = 0
        reversals.removeAll()
        fired = false
    }
}

public enum TransformNaming {
    /// Output next to the source: same name with a new extension, an optional suffix,
    /// and a number when the name is taken. Never returns the source itself.
    public static func output(for source: URL, suffix: String?, ext: String, existing: Set<String>) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        var stem = suffix.map { "\(base) \($0)" } ?? base
        if suffix == nil, ext.lowercased() == source.pathExtension.lowercased() { stem = "\(base) converted" }
        let taken = FileNameKey.keys(existing)
        var name = "\(stem).\(ext)"
        var index = 2
        while taken.contains(FileNameKey.key(name)) {
            name = "\(stem) \(index).\(ext)"
            index += 1
        }
        return source.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Batch rename pattern: {name} original name, {n} position (1-based), {date} yyyy-MM-dd.
    public static func rename(pattern: String, original: String, index: Int, date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return
            pattern
            .replacingOccurrences(of: "{name}", with: original)
            .replacingOccurrences(of: "{n}", with: "\(index)")
            .replacingOccurrences(of: "{date}", with: day)
    }
}

public enum TransformMath {
    /// Scales down so the longest side is at most `longestSide`; never scales up.
    public static func fit(_ size: CGSize, longestSide: CGFloat) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > longestSide, longest > 0 else { return size }
        let scale = longestSide / longest
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// "5.1 MB → 1.3 MB · 75% smaller".
    public static func savingsText(before: Int64, after: Int64) -> String {
        guard before > 0 else { return "" }
        let change = Int((abs(Double(before - after)) / Double(before) * 100).rounded())
        let word = after <= before ? "smaller" : "larger"
        return "\(megabytes(before)) → \(megabytes(after)) · \(change)% \(word)"
    }

    private static func megabytes(_ bytes: Int64) -> String {
        let value = Double(bytes) / 1_000_000
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) MB" : String(format: "%.1f MB", rounded)
    }
}
