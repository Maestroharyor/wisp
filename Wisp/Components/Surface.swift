import SwiftUI
import WispCore

/// What a translucent surface is for, which decides how much it shows through.
enum SurfaceRole {
    /// A floating panel of its own: the mini player, clipboard, quick pocket.
    case panel
    /// A bar or card floating over other content, such as the approval bar.
    case card
}

/// Wisp's floating surfaces, made the way Apple makes its own: Liquid Glass on macOS 26, a
/// system material before it, following Light and Dark. How clear the glass is and how much
/// violet it takes come from Settings › Appearance › Panels. With Reduce Transparency the
/// surface is solid.
private struct WispSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let role: SurfaceRole
    let preferences: Preferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background { background }
            // A hairline keeps the edge readable where glass meets a similar background; glass
            // on macOS 26 draws its own edge light, so it's fainter there.
            .overlay(shape.strokeBorder(Color.primary.opacity(hairline), lineWidth: 0.5).allowsHitTesting(false))
    }

    private var look: Appearance { preferences.appearance }

    private var hairline: Double {
        if contrast == .increased { return 0.35 }
        if #available(macOS 26, *) { return 0.06 }
        return 0.12
    }

    /// Window background laid over the glass: more for Frosted and for cards, which sit on
    /// busier content, so text always reads.
    private var backing: Double {
        min(look.panelGlass.backing + (role == .card ? 0.15 : 0), 0.85)
    }

    private var tint: Color { Color.wispViolet.opacity(look.panelTint * 0.35) }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *) {
            ZStack {
                Color.clear.glassEffect(glass, in: shape)
                shape.fill(Color(nsColor: .windowBackgroundColor).opacity(backing))
                shape.fill(tint)
            }
        } else {
            ZStack {
                shape.fill(material)
                shape.fill(Color(nsColor: .windowBackgroundColor).opacity(backing / 2))
                shape.fill(tint)
            }
        }
    }

    @available(macOS 26, *)
    private var glass: Glass {
        look.panelGlass == .clear ? .clear : .regular
    }

    private var material: Material {
        switch look.panelGlass {
        case .clear: .ultraThinMaterial
        case .tinted: .regularMaterial
        case .frosted: .thickMaterial
        }
    }
}

extension View {
    /// A translucent Wisp surface in `shape` (see `WispSurface`).
    func wispSurface<S: InsettableShape>(_ shape: S, role: SurfaceRole = .panel) -> some View {
        modifier(WispSurface(shape: shape, role: role, preferences: .shared))
    }

    /// A rounded, continuous-cornered Wisp surface.
    func wispSurface(cornerRadius: CGFloat, role: SurfaceRole = .panel) -> some View {
        wispSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), role: role)
    }
}
