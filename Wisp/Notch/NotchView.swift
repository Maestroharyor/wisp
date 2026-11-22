import AppKit
import SwiftUI
import WispCore

/// Draws the notch (or island) for one display and morphs it between states.
/// The panel never resizes; only the shape inside it does.
struct NotchView: View {
    let model: NotchModel

    var body: some View {
        let panel = model.layout.panelFrame
        let surface = model.local(model.surfaceRect)
        let flare = model.drawsNotch ? radii.top : 0
        let side = model.layout.edge.isSide
        // A pulled notch stretches its shape down from the edge it hangs from; the content
        // inside keeps its size rather than being smeared with it.
        let stretch = CGSize(
            width: (surface.width + (side ? 0 : flare * 2)) * model.pull * 0.12,
            height: surface.height * model.pull * 0.45)

        ZStack(alignment: .topLeading) {
            // Under the shell, so bubbles split out from behind the pill's ends.
            BubbleLayer(model: model)
                .frame(width: panel.width, height: panel.height)
            IdleEarsLayer(model: model)
                .frame(width: panel.width, height: panel.height)
            NotchPetLayer(model: model)
                .frame(width: panel.width, height: panel.height)
            SurfaceView(model: model, radii: radii)
                // The flares run along the edge: sideways at the top, up and down on the sides.
                .frame(
                    width: surface.width + (side ? 0 : flare * 2) + stretch.width,
                    height: surface.height + (side ? flare * 2 : 0) + stretch.height
                )
                .position(x: surface.midX, y: surface.midY + stretch.height / 2)
                .modifier(FormChange(model: model))

            if model.isOrb {
                // Stays mounted: the glyph shrinks into what grows out of the orb and comes
                // back as it folds away, rather than popping.
                // Rides with a form change, so the face travels with the shell rather than
                // waiting at the new spot.
                let closed = model.layout.closedRect
                let centre = model.morphFrom.map { CGPoint(x: $0.midX, y: $0.midY) }
                let orb = model.local(
                    centre.map {
                        CGRect(
                            x: $0.x - closed.width / 2, y: $0.y - closed.height / 2, width: closed.width,
                            height: closed.height)
                    }
                        ?? closed)
                let resting = model.spec == .closed || model.spec == .peek
                OrbFace(model: model)
                    .frame(width: orb.width, height: orb.height)
                    .scaleEffect(resting || !model.motion.expands ? 1 : 0.6)
                    .opacity(resting ? 1 : 0)
                    .animation(resting ? model.motion.surfaceClose : model.motion.contentOut, value: resting)
                    .position(x: orb.midX, y: orb.midY)
                    .allowsHitTesting(false)
                    .modifier(FormChange(model: model))
            }

            if model.showsShelfHandle {
                let size = ShelfResizeHandle.size
                ShelfResizeHandle(model: model)
                    .frame(width: size.width, height: size.height)
                    // On the edge away from the shell's anchor: the bottom, or the top for an orb
                    // low on the screen, whose shelf opens upward.
                    .position(
                        x: surface.midX,
                        y: ShelfHeight.growsUp(in: model.layout)
                            ? surface.minY + ShelfResizeHandle.inset : surface.maxY - ShelfResizeHandle.inset
                    )
                    .transition(.opacity)
            }

            if let pill = model.navPillRect.map(model.local) {
                NavPill(model: model)
                    .frame(width: pill.width, height: pill.height)
                    .position(x: pill.midX, y: pill.midY)
                    .transition(.navDrop(model.motion, ride: navRide(pill), drift: navDrift))
            }
        }
        // The orb (or the pill on it) steps aside while the ring is open over it, so its icon
        // doesn't show through the ring's middle.
        .opacity(ringOpenOverOrb ? 0 : 1)
        .animation(.wispDismiss, value: ringOpenOverOrb)
        // The nav pill's labels, drawn over the shell.
        .hoverHintHost()
        .overlay {
            ConfettiLayer(model: model)
                .allowsHitTesting(false)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        // The one surface animation for the shell and everything that moves with it.
        .animation(model.surfaceAnimation, value: model.spec)
        .environment(\.colorScheme, .dark)
        .environment(\.valueFont, model.preferences.appearance.valueFont)
        .environment(\.contextThresholds, model.preferences.contextThresholds)
    }

    private var ringOpenOverOrb: Bool {
        guard model.isOrb, let origin = model.services.ring.openAround else { return false }
        return model.layout.closedRect.insetBy(dx: -8, dy: -8).contains(origin)
    }

    /// How far the nav pill travels on close to fold back into the closed shape, in panel
    /// coordinates (y down).
    private func navRide(_ pill: CGRect) -> CGSize {
        let closed = model.local(model.layout.closedRect)
        switch model.layout.edge {
        case .top: return CGSize(width: 0, height: -(pill.maxY - closed.maxY))
        case .bottom: return CGSize(width: 0, height: closed.minY - pill.minY)
        case .left, .right: return CGSize(width: closed.midX - pill.midX, height: closed.midY - pill.midY)
        }
    }

    /// The pill settles in from the shelf's side: down from under it, or up on the bottom edge.
    private var navDrift: CGSize {
        CGSize(width: 0, height: model.layout.edge == .bottom ? 12 : -12)
    }

    /// Roundness scales every corner except the closed notch's, which has to match the
    /// camera housing.
    private var radii: (top: CGFloat, bottom: CGFloat) {
        let height = model.notchHeight
        let round = CGFloat(model.preferences.appearance.roundness)
        guard model.drawsNotch else {
            let orb = model.layout.placement == .floating
            switch model.spec {
            case .closed, .peek:
                return (0, orb ? model.layout.peekRect.height / 2 : ShellMetrics.closedIslandRadius * round)
            case .compact:
                return (0, (orb ? ShellMetrics.floatingPillRadius : ShellMetrics.closedIslandRadius) * round)
            case .medium, .notification:
                return (0, (orb ? ShellMetrics.floatingCardRadius : ShellMetrics.expandedHUDBottomRadius) * round)
            case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
                return (0, (orb ? ShellMetrics.floatingShelfRadius : ShellMetrics.expandedIslandRadius) * round)
            }
        }
        switch model.spec {
        case .closed, .peek, .compact:
            return (ShellMetrics.closedTopRadius(height: height), ShellMetrics.closedBottomRadius(height: height))
        case .medium, .notification:
            return (ShellMetrics.closedTopRadius(height: height), ShellMetrics.expandedHUDBottomRadius * round)
        case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
            return (ShellMetrics.expandedTopRadius * round, ShellMetrics.expandedShelfBottomRadius * round)
        }
    }
}

/// The black shell plus whatever it currently shows.
private struct SurfaceView: View {
    let model: NotchModel
    let radii: (top: CGFloat, bottom: CGFloat)

    var body: some View {
        let isOpen = model.phase == .open
        let shape = ShellShape(
            notchStyle: model.drawsNotch, edge: model.layout.edge, topRadius: radii.top, bottomRadius: radii.bottom)
        let flare = model.drawsNotch ? radii.top : 0
        let side = model.layout.edge.isSide
        let look = model.preferences.appearance
        let see = isOpen && look.surface != .glass ? look.opacity : 1

        ZStack(alignment: .top) {
            // Solid black that grows and shrinks with the shell, so the morph is always
            // visible. The open style (violet tint, glass) fades in over it rather than
            // replacing it, which would leave the growing shell see-through.
            ZStack {
                Color.black
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !shimmering)) { context in
                    SurfaceBackground(
                        style: look.surface,
                        glass: look.glassEdge,
                        accent: model.accent,
                        glow: model.glow,
                        edge: model.layout.edge,
                        intensity: look.glowIntensity,
                        spread: look.glowSpread,
                        shimmer: shimmering ? context.date.timeIntervalSinceReferenceDate : nil
                    )
                }
                .opacity(isOpen ? 1 : 0)
                if look.grain != .off {
                    GrainTexture().opacity(isOpen ? look.grain.opacity : 0)
                }
            }
            .opacity(see)
            content
                // While a pull opens the shelf, the content shows as the shell makes room for it.
                .opacity(model.pullProgress.map { min(max(($0 - 0.15) * 1.6, 0), 1) } ?? 1)
                // Hover labels stay inside the shell, clear of the flares, since the clip below would cut them.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .hoverHintHost(topInset: hintTopInset)
                .padding(.horizontal, side ? 0 : flare)
                .padding(.vertical, side ? flare : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // One clip for every layer, so newly inserted content is cut by the growing shell
        // too rather than showing at its final size beyond it.
        .clipShape(shape)
        .overlay {
            if look.outline != .off {
                // Fades in with the open style; the closed notch stays a plain black cutout.
                shape.stroke(
                    LinearGradient(
                        colors: [model.accent.opacity(0.15), model.accent.opacity(0.55), model.glow.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: look.outline.lineWidth
                )
                .opacity(isOpen ? 1 : 0)
            }
        }
        .overlay {
            // Over windows the orb's pills, cards and shelf need an edge to read as panels.
            if model.isOrb, model.spec != .closed, model.spec != .peek {
                shape.stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
        .overlay { RimGlow(model: model, shape: shape) }
        .overlay { FinishFlash(model: model, shape: shape) }
        .compositingGroup()
        .shadow(
            color: .black.opacity(closedShadow ?? min(look.shadow.opacity, isOpen ? 1 : 0.5)),
            radius: isOpen ? look.shadow.radius : (model.isOrb ? 10 : 6), y: isOpen ? 8 : (model.isOrb ? 4 : 2)
        )
        .modifier(HoverWobble(model: model))
        .contentShape(shape)
    }

    /// Content runs behind the camera housing on the top edge; labels stay below it.
    private var hintTopInset: CGFloat {
        model.isNotchStyle && model.layout.edge == .top ? model.notchHeight : 0
    }

    /// A notch at rest casts no shadow; the orb floats over windows, so it keeps a soft one.
    private var closedShadow: Double? {
        guard model.spec == .closed else { return nil }
        return model.isOrb ? 0.35 : 0
    }

    /// The aurora drift runs only while the shelf is open and motion is allowed.
    private var shimmering: Bool {
        model.preferences.appearance.shimmer && model.phase == .open && !model.reduceMotion
    }

    /// Content unfolds out of an edge, or blooms out of the orb.
    private var reveal: AnyTransition {
        model.isOrb ? .bloom(model.motion, from: model.bloomOrigin, pill: false) : .unfold(model.motion)
    }

    private var pillReveal: AnyTransition {
        model.isOrb ? .bloom(model.motion, from: model.bloomOrigin, pill: true) : .wingReveal(model.motion)
    }

    @ViewBuilder private var content: some View {
        switch model.spec {
        case .closed, .peek:
            // The orb's face speaks for itself; the notch and islands get an element here.
            if model.isOrb {
                Color.clear
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel("Wisp")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens the shelf")
                    .accessibilityAction { model.onAccessibilityOpen() }
            }
        case .compact:
            if let activity = model.activity {
                Group {
                    if model.layout.edge.isSide {
                        SideActivityView(activity: activity, model: model)
                    } else {
                        CompactActivityView(activity: activity, model: model)
                    }
                }
                .modifier(PillAccessibility(activity: activity, model: model))
                .id(activity.kindKey)
                .transition(pillReveal)
            }
        case .medium:
            if let activity = model.activity {
                MediumActivityView(activity: activity, model: model)
                    .modifier(PillAccessibility(activity: activity, model: model))
                    .id(activity.kindKey)
                    .transition(reveal)
            }
        case .notification:
            if case .agentApproval(let approval) = model.activity {
                AgentApprovalCard(approval: approval, model: model)
                    .id(approval.id)
                    .transition(reveal)
            }
            if case .meetingSoon(let invite) = model.activity {
                MeetingSoonCard(invite: invite, model: model)
                    .id(invite.id)
                    .transition(reveal)
            }
            if case .downloadDone(let download) = model.activity {
                DownloadDoneCard(download: download, model: model)
                    .id(download.path)
                    .transition(reveal)
            }
            if case .aiResult(let card) = model.activity {
                AIResultCardView(card: card, model: model)
                    .id(card.id)
                    .transition(reveal)
            }
            if case .agentCallout(let callout) = model.activity {
                AgentCalloutCard(callout: callout, model: model)
                    .id(callout.id)
                    .transition(reveal)
            }
            if case .agentAway(let summary) = model.activity {
                AgentAwayCard(summary: summary, model: model)
                    .transition(reveal)
            }
            if case .quickIntent(let intent) = model.activity {
                QuickIntentCard(intent: intent, model: model)
                    .transition(reveal)
            }
            if case .meeting(let status) = model.activity, model.showsMeetingControls {
                MeetingControlsCard(status: status, model: model)
                    .transition(reveal)
            }
            if case .notification(let item) = model.activity {
                NotificationCardView(item: item, model: model)
                    .id(item.id)
                    .transition(reveal)
            }
        case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
            ShelfContent(model: model)
                .transition(reveal)
        }
    }
}

/// Notch silhouette (flares into the menu bar, or into the screen edge on the sides) or a
/// plain rounded island.
private struct ShellShape: Shape {
    let notchStyle: Bool
    let edge: ScreenEdge
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if notchStyle, edge.isSide {
            // The top notch drawn on its side: its flat top edge becomes the screen edge.
            let upright = CGRect(x: 0, y: 0, width: rect.height, height: rect.width)
            let path = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: upright)
            let transform =
                edge == .left
                ? CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: rect.minX, ty: rect.minY)
                : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.maxX, ty: rect.minY)
            return path.applying(transform)
        }
        if notchStyle, edge == .bottom {
            // The top notch upside down: its flat edge sits on the Dock or the screen's edge.
            let path = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
            return path.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.minY + rect.maxY))
        }
        if notchStyle {
            return NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
        }
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

/// The open surface: black (with an optional translucent "melt" at the bottom edge),
/// Liquid Glass, or black with a soft accent glow.
struct SurfaceBackground: View {
    let style: SurfaceStyle
    let glass: GlassEdge
    let accent: Color
    /// The right-hand glow; equal to the accent for one-colour themes.
    var glow: Color?
    /// The edge the shell grows from. Gradients are written for the top and turned to match.
    var edge: ScreenEdge = .top
    /// Strength and reach of the tinted glows (1 is the standard look).
    var intensity: Double = 1
    var spread: Double = 1
    /// Seconds, when the glows drift slowly; nil holds them still.
    var shimmer: Double?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch style {
        case .black: black
        // With Reduce Transparency the glass is solid, like the black surface.
        case .glass: if reduceTransparency { black } else { liquidGlass }
        case .tinted: tinted
        }
    }

    @ViewBuilder private var liquidGlass: some View {
        if #available(macOS 26.0, *) {
            // A dark wash keeps white text readable over bright wallpapers.
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular.tint(accent.opacity(0.18)), in: Rectangle())
                .overlay(Color.black.opacity(0.42))
                .overlay(notchShade)
        } else {
            ZStack {
                VisualEffectBlur()
                Color.black.opacity(0.55)
                accent.opacity(0.08)
                notchShade
            }
        }
    }

    /// Colour lives low and in the corners, away from the camera: two soft glows rise from
    /// the bottom corners with a faint wash between, so nothing points at the notch.
    private var right: Color { glow ?? accent }

    private var tinted: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [accent.opacity(0.34 * intensity), accent.opacity(0.08 * intensity), .clear],
                center: oriented(UnitPoint(x: 0.12 + drift, y: 1.15)), startRadius: 0, endRadius: 240 * spread)
            RadialGradient(
                colors: [right.opacity(0.3 * intensity), right.opacity(0.06 * intensity), .clear],
                center: oriented(UnitPoint(x: 0.88 - drift, y: 1.15)), startRadius: 0, endRadius: 240 * spread)
            LinearGradient(
                colors: [.clear, accent.opacity(0.1 * intensity)], startPoint: .center, endPoint: oriented(.bottom)
            )
            .overlay(
                LinearGradient(
                    colors: [accent.opacity(0.06 * intensity), right.opacity(0.06 * intensity)],
                    startPoint: oriented(.leading), endPoint: oriented(.trailing))
            )
            notchShade
        }
    }

    /// How far the two glows have wandered toward the middle, for the shimmer.
    private var drift: Double {
        guard let shimmer else { return 0 }
        return 0.12 * sin(shimmer * 2 * .pi / 9)
    }

    /// Solid black across the top that fades out lower down, so the camera housing melts
    /// into the shelf instead of sitting on a lit background.
    private var notchShade: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.28),
                .init(color: .black.opacity(0), location: 0.6),
            ],
            startPoint: oriented(.top), endPoint: oriented(.bottom))
    }

    /// A point given as if the shell hung from the top (x along the edge, y away from it),
    /// moved to the actual edge.
    private func oriented(_ point: UnitPoint) -> UnitPoint {
        switch edge {
        case .top: point
        case .bottom: UnitPoint(x: point.x, y: 1 - point.y)
        case .left: UnitPoint(x: point.y, y: point.x)
        case .right: UnitPoint(x: 1 - point.y, y: point.x)
        }
    }

    @ViewBuilder private var black: some View {
        if glass == .off {
            Color.black
        } else {
            ZStack {
                VisualEffectBlur()
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.68),
                        .init(color: .black.opacity(glass.bottomOpacity), location: 1),
                    ],
                    startPoint: oriented(.top),
                    endPoint: oriented(.bottom)
                )
            }
        }
    }
}

/// Behind-window blur so the melt picks up the wallpaper colour.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The resting orb: Wisp's glyph, a violet ring while an agent works, and a count of
/// requests waiting for an answer.
private struct OrbFace: View {
    let model: NotchModel

    var body: some View {
        let agents = model.services.agents
        let waiting = agents.approvals.count
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let working = agents.sessions.anyWorking(now: context.date)
            ZStack {
                OrbGlass(lifted: model.spec == .peek)
                OrbEmber(lifted: model.spec == .peek, reduceMotion: model.reduceMotion)
                if waiting > 0 {
                    Circle().strokeBorder(Color.orange, lineWidth: 2)
                } else if working {
                    WorkingSweep(reduceMotion: model.reduceMotion)
                }
            }
        }
        .scaleEffect(model.spec == .peek ? 1.06 : 1)
        .animation(model.reduceMotion ? nil : .wispControl, value: model.spec == .peek)
        .overlay(alignment: .topTrailing) {
            if waiting > 0 {
                Text("\(waiting)")
                    .font(.system(size: 10, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(Capsule().fill(.orange).shadow(color: .black.opacity(0.35), radius: 2, y: 1))
                    .offset(x: 4, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(model.reduceMotion ? nil : .wispPopover, value: waiting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(waiting: waiting, working: agents.sessions.anyWorking(now: .now)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onAccessibilityOpen() }
        .accessibilityAction(named: "Open ring") { model.onAccessibilityRing() }
    }

    /// The sweep and the badge only show; this says the same.
    private func spoken(waiting: Int, working: Bool) -> String {
        if waiting > 0 { return "Wisp, \(waiting) waiting for you" }
        return working ? "Wisp, an agent is working" : "Wisp"
    }
}

/// The orb's surface: Liquid Glass on macOS 26, a deep violet sphere elsewhere, with a soft
/// highlight on top and a thin rim.
private struct OrbGlass: View {
    let lifted: Bool

    var body: some View {
        ZStack {
            if #available(macOS 26, *) {
                Circle().fill(.black.opacity(0.55))
                    .glassEffect(.regular.tint(Color.wispViolet.opacity(0.22)), in: Circle())
            } else {
                Circle().fill(
                    RadialGradient(
                        colors: [Color.wispViolet.opacity(0.45), Color(white: 0.06)], center: UnitPoint(x: 0.5, y: 0.2),
                        startRadius: 2, endRadius: 30))
            }
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 12)
                .offset(y: -12)
                .blur(radius: 1)
            Circle().strokeBorder(.white.opacity(lifted ? 0.32 : 0.18), lineWidth: 1)
        }
    }
}

/// Wisp's flame at the orb's heart: white-hot at its base and violet at its tip, on an ember
/// glow, inside a thin orbit like the ring's. Pointed at, it brightens and breathes; it's
/// still at rest, so an idle orb costs nothing to draw.
private struct OrbEmber: View {
    let lifted: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.wispViolet.opacity(lifted ? 0.85 : 0.5), Color.wispViolet.opacity(0)],
                        center: UnitPoint(x: 0.5, y: 0.58), startRadius: 0, endRadius: 15)
                )
                .padding(2)
                .keyframeAnimator(initialValue: CGFloat(1), repeating: lifted && !reduceMotion) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    CubicKeyframe(1.14, duration: 0.9)
                    CubicKeyframe(1, duration: 0.9)
                }
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color.wispViolet, .white.opacity(0.55), Color.wispViolet, .white.opacity(0.55),
                            Color.wispViolet,
                        ],
                        center: .center),
                    lineWidth: 1
                )
                .padding(4)
                .opacity(lifted ? 0.95 : 0.6)
            Image("MenuGlyph")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 17, height: 17)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.78, green: 0.74, blue: 1)], startPoint: .bottom, endPoint: .top)
                )
                .shadow(color: Color.wispViolet.opacity(lifted ? 0.9 : 0.6), radius: lifted ? 6 : 3)
        }
        .animation(reduceMotion ? nil : .wispControl, value: lifted)
    }
}

/// A violet arc running round the orb while an agent works; a still ring with Reduce Motion.
private struct WorkingSweep: View {
    let reduceMotion: Bool
    @State private var turning = false

    var body: some View {
        if reduceMotion {
            Circle().strokeBorder(Color.wispViolet, lineWidth: 2)
        } else {
            Circle()
                .trim(from: 0, to: 0.32)
                .stroke(
                    AngularGradient(colors: [.clear, Color.wispViolet], center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .padding(1.25)
                .rotationEffect(.degrees(turning ? 360 : 0))
                .animation(.linear(duration: 1.6).repeatForever(autoreverses: false), value: turning)
                .onAppear { turning = true }
        }
    }
}

/// The shell changing form: an orb torn off the notch growing under the pointer, and
/// shrinking away as an orb docks. Scales about the closed shape.
private struct FormChange: ViewModifier {
    let model: NotchModel

    func body(content: Content) -> some View {
        let panel = model.layout.panelFrame
        let closed = model.local(model.layout.closedRect)
        let anchor =
            panel.width > 0 && panel.height > 0
            ? UnitPoint(x: closed.midX / panel.width, y: closed.midY / panel.height) : .center
        content
            .scaleEffect(model.vanishing ? 0.2 : 1, anchor: anchor)
            .opacity(model.vanishing ? 0 : 1)
            // Keyframes start from the small size themselves, so the spring always shows
            // rather than depending on a frame being drawn in between.
            .keyframeAnimator(initialValue: CGFloat(1), trigger: model.pops) { view, scale in
                view.scaleEffect(scale, anchor: anchor)
            } keyframes: { _ in
                LinearKeyframe(0.85, duration: 0.001)
                SpringKeyframe(1, duration: 0.4, spring: SpringTuning.formMorph.spring)
                // A spring cut off by its duration can stop short of 1, leaving the shell a hair
                // small and off its screen edge; this lands it exactly.
                LinearKeyframe(1, duration: 0.05)
            }
    }
}
