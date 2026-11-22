import AppKit
import SwiftUI
import WispCore

extension View {
    /// `animation(_:value:)` that drops the animation under Reduce Motion, so changes land at once.
    func wispAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReduceMotionAnimation(animation: animation, value: value))
    }

    /// `transition(_:)` that becomes a plain fade under Reduce Motion, since scaling and sliding
    /// are what the setting asks to avoid.
    func wispTransition(_ transition: AnyTransition) -> some View {
        modifier(ReduceMotionTransition(transition: transition))
    }

    /// A soft rounded highlight under the pointer, for rows and tiles that act on a click.
    func wispHover(cornerRadius: CGFloat = SurfaceRadius.control) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

/// `withAnimation` for imperative code that has no view environment to read. Under Reduce
/// Motion the change happens without animation.
@MainActor
func withWispAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        return try body()
    }
    return try withAnimation(animation, body)
}

private struct ReduceMotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct ReduceMotionTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .wispControl, value: hovering)
    }
}
