import Foundation

/// The Mac's default point size for each text style, so the window and Settings can grow text
/// by the Text size setting. SwiftUI's Dynamic Type sizes don't change text on macOS.
public enum TextStyleSize: CaseIterable, Sendable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2

    public var basePoints: Double {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        }
    }

    /// Headline is body size, set in bold.
    public var isBold: Bool { self == .headline }

    public func points(scale: Double) -> Double {
        Self.scaled(basePoints, by: scale)
    }

    /// Half points keep scaled text crisp without drifting far from the factor.
    public static func scaled(_ points: Double, by scale: Double) -> Double {
        (points * scale * 2).rounded() / 2
    }
}
