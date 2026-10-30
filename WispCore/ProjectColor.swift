import Foundation

/// A stable colour per project, so sessions are recognisable at a glance.
public enum ProjectColor {
    /// Hues (0...1) that stay clear of amber (waiting) and green (done).
    public static let palette: [Double] = [0.0, 0.03, 0.55, 0.6, 0.66, 0.74, 0.82, 0.9]

    public static func hue(for project: String) -> Double {
        // FNV-1a: tiny, and stable across launches, unlike `hashValue`.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in project.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
