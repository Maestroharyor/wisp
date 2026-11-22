import CoreGraphics
import Foundation

/// A window Screen Recording can capture, as the app's on-screen windows list it.
public struct CapturableWindow: Equatable, Sendable {
    public let id: UInt32
    public let title: String?
    /// Top-left origin, like Core Graphics and Accessibility.
    public let frame: CGRect

    public init(id: UInt32, title: String?, frame: CGRect) {
        self.id = id
        self.title = title
        self.frame = frame
    }
}

/// Which capturable window an Accessibility window is. Accessibility knows a window's title and
/// frame but not its window number, so the two lists are matched: the same title first (the
/// nearest frame when several share it), else a frame that's all but the same.
public enum WindowMatch {
    /// How far apart two frames may be, in points summed over origin and size, and still be the
    /// same window (rounding and a title bar's shadow differ between the two lists).
    public static let tolerance: CGFloat = 12

    public static func best(for window: WindowSummary, in candidates: [CapturableWindow]) -> UInt32? {
        guard !window.isMinimised, !candidates.isEmpty else { return nil }
        let title = cleaned(window.title)
        if let title {
            let same = candidates.filter { cleaned($0.title) == title }
            if same.count == 1 { return same[0].id }
            if let frame = window.frame,
                let nearest = same.min(by: { distance($0.frame, frame) < distance($1.frame, frame) })
            {
                return nearest.id
            }
            if let first = same.first { return first.id }
        }
        guard let frame = window.frame,
            let nearest = candidates.min(by: { distance($0.frame, frame) < distance($1.frame, frame) }),
            distance(nearest.frame, frame) <= tolerance
        else { return nil }
        return nearest.id
    }

    static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    private static func cleaned(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }
}

/// How big a window preview is drawn: the window's shape, fitted inside a square box.
public enum WindowPreview {
    public static func size(for window: CGSize, fitting side: CGFloat) -> CGSize {
        guard window.width > 0, window.height > 0, side > 0 else { return .zero }
        let scale = min(side / window.width, side / window.height)
        return CGSize(width: (window.width * scale).rounded(), height: (window.height * scale).rounded())
    }
}
