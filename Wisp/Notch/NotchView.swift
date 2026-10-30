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
                    width: surface.width + (side ? 0 : flare * 2), height: surface.height + (side ? flare * 2 : 0)
                )
                .position(x: surface.midX, y: surface.midY)

            if let pill = model.navPillRect.map(model.local) {
                NavPill(model: model)
                    .frame(width: pill.width, height: pill.height)
                    .position(x: pill.midX, y: pill.midY)
                    .transition(.navDrop(model.motion, ride: navRide(pill), drift: navDrift))
            }
        }
        .overlay {
            ConfettiLayer(model: model)
                .allowsHitTesting(false)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .animation(model.surfaceAnimation, value: model.spec)
        .environment(\.colorScheme, .dark)
        .environment(\.valueFont, model.preferences.appearance.valueFont)
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
            switch model.spec {
            case .closed, .peek, .compact: return (0, ShellMetrics.closedIslandRadius * round)
            case .medium, .notification: return (0, ShellMetrics.expandedHUDBottomRadius * round)
            case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
                return (0, ShellMetrics.expandedIslandRadius * round)
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
        .overlay { RimGlow(model: model, shape: shape) }
        .overlay { FinishFlash(model: model, shape: shape) }
        .compositingGroup()
        .shadow(
            color: .black.opacity(model.spec == .closed ? 0 : min(look.shadow.opacity, isOpen ? 1 : 0.5)),
            radius: isOpen ? look.shadow.radius : 6, y: isOpen ? 8 : 2
        )
        .modifier(HoverWobble(model: model))
        // The shell rides the same spring as the frame, so closing visibly folds back
        // into the notch in both directions instead of snapping shut.
        .animation(model.surfaceAnimation, value: model.spec)
        .contentShape(shape)
    }

    /// The aurora drift runs only while the shelf is open and motion is allowed.
    private var shimmering: Bool {
        model.preferences.appearance.shimmer && model.phase == .open && !model.reduceMotion
    }

    @ViewBuilder private var content: some View {
        let motion = model.motion
        switch model.spec {
        case .closed, .peek:
            Color.clear
        case .compact:
            if let activity = model.activity {
                Group {
                    if model.layout.edge.isSide {
                        SideActivityView(activity: activity, model: model)
                    } else {
                        CompactActivityView(activity: activity, model: model)
                    }
                }
                .id(activity.kindKey)
                .transition(.wingReveal(motion))
            }
        case .medium:
            if let activity = model.activity {
                MediumActivityView(activity: activity, model: model)
                    .id(activity.kindKey)
                    .transition(.unfold(motion))
            }
        case .notification:
            if case .agentApproval(let approval) = model.activity {
                AgentApprovalCard(approval: approval, model: model)
                    .id(approval.id)
                    .transition(.unfold(motion))
            }
            if case .meetingSoon(let invite) = model.activity {
                MeetingSoonCard(invite: invite, model: model)
                    .id(invite.id)
                    .transition(.unfold(motion))
            }
            if case .notification(let item) = model.activity {
                NotificationCardView(item: item, model: model)
                    .id(item.id)
                    .transition(.unfold(motion))
            }
        case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
            ShelfContent(model: model)
                .transition(.unfold(motion))
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

    var body: some View {
        switch style {
        case .black: black
        case .glass: liquidGlass
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
