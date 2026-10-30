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
        let flare = model.isNotchStyle ? radii.top : 0

        ZStack(alignment: .topLeading) {
            SurfaceView(model: model, radii: radii)
                .frame(width: surface.width + flare * 2, height: surface.height)
                .position(x: surface.midX, y: surface.midY)

            if let pill = model.navPillRect.map(model.local) {
                NavPill(model: model)
                    .frame(width: pill.width, height: pill.height)
                    .position(x: pill.midX, y: pill.midY)
                    .transition(
                        .navDrop(model.motion, rideDistance: pill.maxY - model.local(model.layout.closedRect).maxY))
            }
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .animation(model.surfaceAnimation, value: model.spec)
        .environment(\.colorScheme, .dark)
    }

    private var radii: (top: CGFloat, bottom: CGFloat) {
        let height = model.notchHeight
        guard model.isNotchStyle else {
            switch model.spec {
            case .closed, .peek, .compact: return (0, ShellMetrics.closedIslandRadius)
            case .medium, .notification: return (0, ShellMetrics.expandedHUDBottomRadius)
            case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
                return (0, ShellMetrics.expandedIslandRadius)
            }
        }
        switch model.spec {
        case .closed, .peek, .compact:
            return (ShellMetrics.closedTopRadius(height: height), ShellMetrics.closedBottomRadius(height: height))
        case .medium, .notification:
            return (ShellMetrics.closedTopRadius(height: height), ShellMetrics.expandedHUDBottomRadius)
        case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
            return (ShellMetrics.expandedTopRadius, ShellMetrics.expandedShelfBottomRadius)
        }
    }
}

/// The black shell plus whatever it currently shows.
private struct SurfaceView: View {
    let model: NotchModel
    let radii: (top: CGFloat, bottom: CGFloat)

    var body: some View {
        let isOpen = model.phase == .open
        let shape = ShellShape(notchStyle: model.isNotchStyle, topRadius: radii.top, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            // Solid black that grows and shrinks with the shell, so the morph is always
            // visible. The open style (violet tint, glass) fades in over it rather than
            // replacing it, which would leave the growing shell see-through.
            Color.black
            SurfaceBackground(
                style: model.preferences.surfaceStyle,
                glass: model.preferences.glassEdge,
                accent: model.accent
            )
            .opacity(isOpen ? 1 : 0)
            content
                .padding(.horizontal, model.isNotchStyle ? radii.top : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // One clip for every layer, so newly inserted content is cut by the growing shell
        // too rather than showing at its final size beyond it.
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: .black.opacity(model.spec == .closed ? 0 : 0.5), radius: isOpen ? 18 : 6, y: isOpen ? 8 : 2)
        // The shell rides the same spring as the frame, so closing visibly folds back
        // into the notch in both directions instead of snapping shut.
        .animation(model.surfaceAnimation, value: model.spec)
        .contentShape(shape)
    }

    @ViewBuilder private var content: some View {
        let motion = model.motion
        switch model.spec {
        case .closed, .peek:
            Color.clear
        case .compact:
            if let activity = model.activity {
                CompactActivityView(activity: activity, model: model)
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

/// Notch silhouette (flares into the menu bar) or a plain rounded island.
private struct ShellShape: Shape {
    let notchStyle: Bool
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
                .overlay(Self.notchShade)
        } else {
            ZStack {
                VisualEffectBlur()
                Color.black.opacity(0.55)
                accent.opacity(0.08)
                Self.notchShade
            }
        }
    }

    /// Colour lives low and in the corners, away from the camera: two soft glows rise from
    /// the bottom corners with a faint wash between, so nothing points at the notch.
    private var tinted: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [accent.opacity(0.34), accent.opacity(0.08), .clear],
                center: UnitPoint(x: 0.12, y: 1.15), startRadius: 0, endRadius: 240)
            RadialGradient(
                colors: [accent.opacity(0.3), accent.opacity(0.06), .clear],
                center: UnitPoint(x: 0.88, y: 1.15), startRadius: 0, endRadius: 240)
            LinearGradient(colors: [.clear, accent.opacity(0.1)], startPoint: .center, endPoint: .bottom)
            Self.notchShade
        }
    }

    /// Solid black across the top that fades out lower down, so the camera housing melts
    /// into the shelf instead of sitting on a lit background.
    private static var notchShade: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.28),
                .init(color: .black.opacity(0), location: 0.6),
            ],
            startPoint: .top, endPoint: .bottom)
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
                    startPoint: .top,
                    endPoint: .bottom
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
