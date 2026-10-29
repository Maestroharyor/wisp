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
            SurfaceBackground(glass: isOpen ? model.preferences.glassEdge : .off)
                .clipShape(shape)
            content
                .padding(.horizontal, model.isNotchStyle ? radii.top : 0)
                .clipShape(shape)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(model.spec == .closed ? 0 : 0.5), radius: isOpen ? 18 : 6, y: isOpen ? 8 : 2)
        .animation(model.spec == .closed ? .easeOut(duration: 0.08) : model.surfaceAnimation, value: model.spec)
        .contentShape(shape)
    }

    /// Content starts at the closed notch's width relative to the open surface.
    private var revealScale: CGFloat {
        SurfaceSizing.revealScale(from: model.layout.closedRect, to: model.surfaceRect)
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
                    .transition(.notchEnlarge(motion, fromScale: revealScale))
            }
        case .notification:
            if case .notification(let item) = model.activity {
                NotificationCardView(item: item, model: model)
                    .id(item.id)
                    .transition(.notchEnlarge(motion, fromScale: revealScale))
            }
        case .home, .tray, .dropTiles, .widgetGrid, .widgetSolo, .media:
            ShelfContent(model: model)
                .transition(.notchEnlarge(motion, fromScale: revealScale))
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

/// Black surface with an optional translucent "melt" at the bottom edge.
private struct SurfaceBackground: View {
    let glass: GlassEdge

    var body: some View {
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
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
