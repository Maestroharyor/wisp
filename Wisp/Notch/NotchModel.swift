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
    var phase: NotchPhase = .closed {
        didSet { if phase == .peek, oldValue == .closed { hoverPulses += 1 } }
    }
    /// Counts pointer arrivals on the closed notch, to replay the hover wobble.
    private(set) var hoverPulses = 0
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
    var homeSnapshot: (layout: HomeLayout, enabled: [WidgetKind], profile: String)?
    /// A file drag is over the notch: show the quick-action tiles.
    var dragging = false
    /// Whether this display shows live activities.
    var showsActivities = true
    /// Set while the user types a reply to a notification card.
    var replyingTo: NotificationItem?
    /// The pointer is on a card that can be closed, so its close button shows.
    var cardHovered = false
    /// The reply typed so far. Kept here, not in the card, because a higher-priority alert
    /// (volume, Caps Lock, an approval) replaces the card for a moment.
    var replyDraft = ""
    /// Lyrics instead of artwork on the Media page. Kept here so closing the shelf or
    /// changing page (which rebuilds the page) doesn't turn them off.
    var showsLyrics = false
    /// Prompt drafts in the Agents detail, per session, so closing the shelf keeps them and
    /// one session's draft never goes to another.
    var agentDrafts: [String: String] = [:]
    /// The session whose draft box is on screen in the Agents view, so dictation can type into
    /// it. Nil while details are private (the box is hidden then).
    var draftClaim: DraftBoxClaim?
    var draftSession: String? { draftClaim?.session }
    /// Dictated text for the question card, taken (and cleared) by the card.
    var dictatedAnswer: DictatedAnswer?
    /// Called by the card when a reply is sent or abandoned.
    var onReplyEnded: () -> Void = {}
    /// A card wants typing (a question's "Other…" answer): the panel takes key status, and
    /// gives it back once that's done.
    var onWantsKey: () -> Void = {}
    var onKeyDone: () -> Void = {}
    /// The approval card opened to show its preview.
    var expandedApproval: UUID?
    /// The meeting pill was clicked open into its call controls.
    var meetingControlsOpen = false
    /// The controls card shows while it's open and the call app has controls to drive.
    var showsMeetingControls: Bool {
        guard meetingControlsOpen, case .meeting = activity else { return false }
        return !services.meetingControls.states.isEmpty
    }
    /// The session whose pill was clicked: the Agents view opens on it.
    var focusedSession: String?
    /// The forms this display can switch to, and the switch itself (the nav pill's form menu).
    var forms: [FormFactor] = FormFactor.allCases
    var onSetForm: (FormFactor) -> Void = { _ in }
    /// The shelf window's pages have no shell of their own; they show the form of the shell
    /// they stand in for.
    var standInForm: FormFactor?
    /// Window while the Window form is on, otherwise the shell's own form.
    var form: FormFactor {
        services.shelfWindow.form(shell: standInForm ?? FormFactor(placement: layout.placement))
    }
    var isOrb: Bool { layout.placement == .floating }
    /// How far a pull on the notch has gone toward tearing it off, 0 to 1 (a rubber band).
    var pull: CGFloat = 0
    /// Counts form changes; each one springs the shell up from smaller.
    var pops = 0
    /// The orb is shrinking away before it docks.
    var vanishing = false
    /// Where the orb sits in the current surface: content blooms out of and back into it.
    var bloomOrigin: UnitPoint {
        let point = OrbGeometry.bloomAnchor(orb: layout.closedRect, surface: surfaceRect)
        return UnitPoint(x: point.x, y: point.y)
    }

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
            if dragging { return .dropTiles(extra: preferences.dropActions.count) }
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
                if case .notification = activity {
                    return .notification(extra: replyingTo != nil ? SurfaceSizing.replyBarHeight : 0)
                }
                if case .agentApproval(let approval) = activity {
                    if approval.prompt == .question { return .notification(extra: SurfaceSizing.questionRowHeight) }
                    // Private mode hides the preview, so the card doesn't keep its room either.
                    let open = expandedApproval == approval.id && !services.agents.detailsHidden
                    return .notification(extra: open ? SurfaceSizing.approvalPreviewHeight : 0)
                }
                if case .meetingSoon = activity { return .notification(extra: 0) }
                if case .downloadDone = activity { return .notification(extra: 0) }
                if showsMeetingControls { return .notification(extra: 0) }
                return activity.isMedium ? .medium : .compact(wide: activity.usesWideWings)
            }
            // Only the grow feedback changes the shape; glow and wobble play on the closed one.
            return phase == .peek && preferences.appearance.hoverFeedback == .grow ? .peek : .closed
        }
    }

    /// The zoom the open shelf's content gets from the shelf size setting.
    var shelfZoom: CGFloat {
        let requested = preferences.appearance.shelfSize.scale
        guard let width = SurfaceSizing.shelfContentWidth(for: spec, in: layout) else { return requested }
        return SurfaceSizing.shelfScale(contentWidth: width, requested: requested, layout: layout)
    }

    var surfaceRect: CGRect {
        let look = preferences.appearance
        return SurfaceSizing.rect(
            for: spec, in: layout, contentScale: look.shelfSize.scale, peekStrength: look.hoverStrength)
    }

    /// Extra live activities beside a compact pill. They merge back into the shell while
    /// it opens or shows a card.
    var bubbles: [ActivityBubble] {
        guard activity != nil, preferences.activityBubbles, case .compact = spec else { return [] }
        return services.activities.bubbles.filter { $0.slot != .media || preferences.mediaActivity }
    }

    var bubbleRects: [CGRect] {
        SurfaceSizing.bubbleRects(
            beside: surfaceRect, count: bubbles.count, firstOnLeft: preferences.firstBubbleOnLeft,
            placement: layout.anchor)
    }

    /// The bubble under a click, if any. Bubbles take clicks but don't open the shelf on hover.
    func bubble(at point: CGPoint) -> ActivityBubble? {
        zip(bubbles, bubbleRects).first { $0.1.insetBy(dx: -3, dy: -3).contains(point) }?.0
    }

    /// The closed shell's rim glow: a beat for music, a slow breath while something works.
    var glowMode: GlowPulse.Mode {
        let look = preferences.appearance
        guard phase != .open, !reduceMotion else { return .off }
        switch activity {
        case .media?:
            if look.musicGlow { return .beat }
            return look.breathingGlow ? .breathing : .off
        case .agent(let status)? where status.state == .running:
            return look.breathingGlow ? .breathing : .off
        case .timer?:
            return look.breathingGlow ? .breathing : .off
        default:
            return .off
        }
    }

    var navPillRect: CGRect? {
        phase == .open && !dragging && preferences.appearance.navPill != .hidden
            ? SurfaceSizing.navPillRect(for: surfaceRect, placement: layout.anchor) : nil
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
    /// The shell is drawn as a notch attached to its edge: at the top in notch style, and
    /// always on the left and right edges.
    var drawsNotch: Bool { isNotchStyle || layout.edge.isSide }
    /// Height of a one-line pill (the notch itself on the top edge).
    var notchHeight: CGFloat { layout.barHeight }
    /// Space above a card's content: the notch it hangs from, or a margin on an island.
    var cardTopInset: CGFloat { isNotchStyle ? notchHeight : 8 }
    /// Notification and two-line cards get a close button; cards with their own buttons
    /// (approvals, Join) and pills don't.
    var showsCloseButton: Bool {
        guard cardHovered, replyingTo == nil, let activity, services.activities.currentSlot?.isDismissable == true
        else { return false }
        if case .notification = activity { return true }
        return activity.isMedium
    }

    var motion: NotchMotion {
        .preset(speed, framesPerSecond: framesPerSecond, reduceMotion: reduceMotion)
    }

    /// Glow and glass tint: the playing album's colour when allowed, otherwise Wisp's violet.
    var accent: Color { services.accent }
    var glow: Color { services.glow }

    /// Bouncier when growing, damped when settling back to the plain notch.
    var surfaceAnimation: Animation {
        spec == .closed ? motion.surfaceClose : motion.surfaceOpen
    }
}

/// Dictated text on its way to a question card's typed answer.
struct DictatedAnswer: Equatable {
    let approval: UUID
    let text: String
    /// Two dictations with the same words are still two changes.
    let id = UUID()
}
