import CoreGraphics

/// Wisp's shell proportions. Open surfaces are generously rounded, a little softer than
/// the hardware notch, so the shelf reads as something that grew out of it.
public enum ShellMetrics {
    /// Concave flare where a closed notch meets the menu bar.
    public static func closedTopRadius(height: CGFloat) -> CGFloat { clamp(height * 0.24, 8, 10) }
    public static func closedBottomRadius(height: CGFloat) -> CGFloat { clamp(height * 0.32, 11, 13) }

    public static let expandedTopRadius: CGFloat = 34
    public static let expandedShelfBottomRadius: CGFloat = 46
    public static let expandedIslandRadius: CGFloat = 50
    public static let expandedHUDBottomRadius: CGFloat = 28
    public static let closedIslandRadius: CGFloat = 20
    public static let widgetCornerRadius: CGFloat = 20
    public static let cardSpacing: CGFloat = 18
    public static let widgetContentHeight: CGFloat = 93
    /// The media widget needs room for artwork, a progress row and controls.
    /// One media widget then gives a shelf of about 180 pt.
    public static let mediaWidgetContentHeight: CGFloat = 122

    public static func shelfMinimumWidth(notchStyle: Bool) -> CGFloat { notchStyle ? 451 : 405 }
    public static func soloCardWidth(notchStyle: Bool) -> CGFloat { notchStyle ? 352 : 370 }

    /// Insets around shelf content; notch style clears the camera housing and the flares.
    public static func shelfInsets(notchStyle: Bool, notchHeight: CGFloat) -> EdgeInsetsValue {
        notchStyle
            ? EdgeInsetsValue(top: notchHeight + 10, leading: 48, bottom: 16, trailing: 48)
            : EdgeInsetsValue(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    public static func hudInsets(notchStyle: Bool, notchHeight: CGFloat) -> EdgeInsetsValue {
        notchStyle
            ? EdgeInsetsValue(top: notchHeight, leading: 48, bottom: 16, trailing: 48)
            : EdgeInsetsValue(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }
}

/// Live-activity proportions: wing widths, row heights and type sizes for the pill and cards.
public enum ActivityMetrics {
    public static let compactNotchWing: CGFloat = 70
    public static let compactIslandWidth: CGFloat = 150
    public static let interactiveNotchWing: CGFloat = 120
    public static let interactiveIslandWidth: CGFloat = 240
    public static let rowHeight: CGFloat = 37
    public static let cardContentHeight: CGFloat = 59
    public static let iconSize: CGFloat = 13
    public static let labelFontSize: CGFloat = 12
    public static let contentSpacing: CGFloat = 6
    public static let islandContentInset: CGFloat = 12
    public static let progressRingSize: CGFloat = 20
    public static let progressRingLineWidth: CGFloat = 2
    public static let controlSize: CGFloat = 24
    /// An upright pill on a left or right edge: an icon above a short value.
    public static let sidePillSize = CGSize(width: 50, height: 88)
    /// Room for longer values (an hour-long timer, a meeting) on a side edge.
    public static let interactiveSidePillSize = CGSize(width: 58, height: 96)

    /// Horizontal padding that centres an icon vertically in the wing.
    public static func symmetricPadding(iconSize: CGFloat, notchHeight: CGFloat, notchStyle: Bool) -> CGFloat {
        let padding = max((notchHeight - iconSize) / 2, 6)
        return notchStyle ? padding + 10 : padding
    }
}

/// A platform-neutral copy of SwiftUI's `EdgeInsets`, so WispCore stays UI-free.
public struct EdgeInsetsValue: Sendable, Equatable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}
