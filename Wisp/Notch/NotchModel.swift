import Observation
import SwiftUI
import WispCore

enum ShelfPage: Hashable {
    case home
    case tray
    case media
    case widgets

    /// Position in the nav pill, left to right.
    var order: Int {
        switch self {
        case .home: 0
        case .tray: 1
        case .media: 2
        case .widgets: 3
        }
    }

    /// From a profile's stored page name; anything unknown is Home.
    init(name: String) {
        switch name {
        case "tray": self = .tray
        case "media": self = .media
        case "widgets": self = .widgets
        default: self = .home
        }
    }
}

/// What the SwiftUI notch view renders for one display.
@MainActor
@Observable
final class NotchModel {
    var phase: NotchPhase = .closed
    var layout: NotchLayout
    var speed: AnimationSpeed = .standard
    var framesPerSecond = 60
    var reduceMotion = false
    /// Choosing any tab, including Widgets again, returns the Widgets page to its grid.
    var page: ShelfPage = .home {
        didSet {
            soloWidget = nil
            pageMovedForward = page.order >= oldValue.order
        }
    }
    /// Whether the last page change went right in the nav pill, so content slides that way.
    private(set) var pageMovedForward = true
    /// The widget opened on its own from the Widgets page grid.
    var soloWidget: WidgetKind?
    var editingHome = false
    /// Widget order when customising began, restored on cancel.
    var homeSnapshot: (layout: HomeLayout, enabled: [WidgetKind])?
    /// A file drag is over the notch: show the quick-action tiles.
    var dragging = false
    /// Whether this display shows live activities.
    var showsActivities = true
    /// Set while the user types a reply to a notification card.
    var replyingTo: NotificationItem?
    /// Called by the card when a reply is sent or abandoned.
    var onReplyEnded: () -> Void = {}

    let services: AppServices

    init(layout: NotchLayout, services: AppServices) {
        self.layout = layout
        self.services = services
    }

    var preferences: Preferences { services.preferences }

    var activity: Activity? {
        guard showsActivities, let current = services.activities.current else { return nil }
        if current == .media, !preferences.mediaActivity { return nil }
        return current
    }

    var spec: SurfaceSpec {
        switch phase {
        case .open:
            if dragging { return .dropTiles }
            switch page {
            case .home:
                return .home(contentWidth: preferences.homeLayout.contentWidth, editing: editingHome)
            case .media: return .media
            case .widgets:
                if let soloWidget { return .widgetSolo(wide: soloWidget.hasDetailPage) }
                let count = preferences.gridWidgets.count
                return .widgetGrid(
                    count: count, rows: WidgetGrid.rows(count: count, preferred: preferences.widgetGridRows))
            case .tray: return .tray(items: services.tray.count)
            }
        case .peek, .closed:
            if let activity {
                if case .notification = activity { return .notification(replying: replyingTo != nil) }
                if case .agentApproval = activity { return .notification(replying: false) }
                if case .meetingSoon = activity { return .notification(replying: false) }
                return activity.isMedium ? .medium : .compact(wide: activity.usesWideWings)
            }
            return phase == .peek ? .peek : .closed
        }
    }

    var surfaceRect: CGRect { SurfaceSizing.rect(for: spec, in: layout) }

    /// Extra live activities beside a compact pill. They merge back into the shell while
    /// it opens or shows a card.
    var bubbles: [ActivityBubble] {
        guard activity != nil, preferences.activityBubbles, case .compact = spec else { return [] }
        return services.activities.bubbles.filter { $0.slot != .media || preferences.mediaActivity }
    }

    var bubbleRects: [CGRect] { SurfaceSizing.bubbleRects(beside: surfaceRect, count: bubbles.count) }

    /// The bubble under a click, if any. Bubbles take clicks but don't open the shelf on hover.
    func bubble(at point: CGPoint) -> ActivityBubble? {
        zip(bubbles, bubbleRects).first { $0.1.insetBy(dx: -3, dy: -3).contains(point) }?.0
    }

    var navPillRect: CGRect? {
        phase == .open && !dragging ? SurfaceSizing.navPillRect(below: surfaceRect) : nil
    }

    /// Screen areas that count as "on the notch" for hover and clicks.
    var hitRegions: [CGRect] {
        [layout.hitRegion(for: surfaceRect)] + (navPillRect.map { [$0.insetBy(dx: -4, dy: -4)] } ?? [])
    }

    func contains(_ point: CGPoint) -> Bool { hitRegions.contains { $0.contains(point) } }

    /// Converts a global rect to the panel's top-left coordinate space.
    func local(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - layout.panelFrame.minX,
            y: layout.panelFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    var isNotchStyle: Bool { layout.style == .notch }
    var notchHeight: CGFloat { layout.closedRect.height }

    var motion: NotchMotion {
        .preset(speed, framesPerSecond: framesPerSecond, reduceMotion: reduceMotion)
    }

    /// Glow and glass tint: the playing album's colour when allowed, otherwise Wisp's violet.
    var accent: Color { services.accent }

    /// Bouncier when growing, damped when settling back to the plain notch.
    var surfaceAnimation: Animation {
        spec == .closed ? motion.surfaceClose : motion.surfaceOpen
    }
}
