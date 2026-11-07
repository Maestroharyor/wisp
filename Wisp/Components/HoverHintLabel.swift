import AppKit
import SwiftUI
import WispCore

extension View {
    /// Names an icon-only control. After a short rest the hovered control shows a small label,
    /// drawn by the nearest `hoverHintHost()`, since the notch panel never gets system tooltips.
    /// `help` also sets a system tooltip (and the VoiceOver hint), for an ordinary window; leave
    /// it nil when it would only repeat the accessibility label. With a tooltip, the label skips
    /// itself whenever that tooltip would show.
    func hoverHint(_ text: String, edge: HoverHint.Edge = .top, help: String? = nil) -> some View {
        modifier(HoverHintModifier(text: text, edge: edge, help: help))
    }

    /// Draws the hover labels of the controls inside, kept within this view's bounds (less
    /// `topInset`) so a clipping surface never cuts them off. Labels don't travel further up.
    func hoverHintHost(topInset: CGFloat = 0) -> some View {
        modifier(HoverHintHost(topInset: topInset))
    }
}

private struct HoverHintRequest: Equatable {
    let text: String
    let edge: HoverHint.Edge
    let anchor: Anchor<CGRect>
}

private struct HoverHintKey: PreferenceKey {
    static var defaultValue: HoverHintRequest? { nil }

    static func reduce(value: inout HoverHintRequest?, nextValue: () -> HoverHintRequest?) {
        value = nextValue() ?? value
    }
}

extension EnvironmentValues {
    /// Counts clicks anywhere in a hover hint host, so a click hides the label it was over.
    @Entry fileprivate var hoverHintClicks = 0
}

/// Sets `.help` only when there is a tooltip to show.
private struct OptionalHelp: ViewModifier {
    let help: String?

    func body(content: Content) -> some View {
        if let help { content.help(help) } else { content }
    }
}

private struct HoverHintModifier: ViewModifier {
    let text: String
    let edge: HoverHint.Edge
    let help: String?

    @Environment(\.controlActiveState) private var activeState
    @Environment(\.hoverHintClicks) private var clicks
    @State private var hovering = false
    /// Clicked while hovering: no label until the pointer leaves and comes back.
    @State private var dismissed = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .modifier(OptionalHelp(help: help))
            .onHover { inside in
                hovering = inside
                if !inside {
                    shown = false
                    dismissed = false
                }
            }
            .onChange(of: clicks) {
                shown = false
                if hovering { dismissed = true }
            }
            // Keyed on whether a label may show, so leaving or clicking cancels a pending one.
            .task(id: hovering && !dismissed) {
                guard hovering, !dismissed else { return }
                do {
                    try await Task.sleep(for: HoverHint.delay)
                } catch {
                    return
                }
                // A key window of the active app shows the system tooltip instead.
                guard help == nil || !(activeState == .key && NSApp.isActive) else { return }
                shown = true
            }
            .anchorPreference(key: HoverHintKey.self, value: .bounds) { anchor in
                shown ? HoverHintRequest(text: text, edge: edge, anchor: anchor) : nil
            }
    }
}

private struct HoverHintHost: ViewModifier {
    let topInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clicks = 0

    func body(content: Content) -> some View {
        content
            .environment(\.hoverHintClicks, clicks)
            .overlayPreferenceValue(HoverHintKey.self) { request in
                GeometryReader { proxy in
                    if let request {
                        HoverHintBubble(
                            text: request.text, edge: request.edge, anchor: proxy[request.anchor],
                            bounds: CGRect(
                                x: 0, y: topInset, width: proxy.size.width,
                                height: max(0, proxy.size.height - topInset))
                        )
                        .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: request)
            }
            .transformPreference(HoverHintKey.self) { $0 = nil }
            // At the host rather than on each control, so it never takes a row's own tap.
            .simultaneousGesture(TapGesture().onEnded { clicks &+= 1 })
    }
}

private struct HoverHintBubble: View {
    let text: String
    let edge: HoverHint.Edge
    let anchor: CGRect
    let bounds: CGRect

    @State private var size = CGSize.zero

    var body: some View {
        let placement = HoverHint.placement(preferred: edge, anchor: anchor, label: size, bounds: bounds)
        Text(text)
            .font(.caption)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color(white: 0.12).opacity(0.96))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            )
            .fixedSize()
            .background {
                GeometryReader { label in
                    Color.clear
                        .onAppear { size = label.size }
                        .onChange(of: label.size) { _, new in size = new }
                }
            }
            // Hidden until measured, so it never shows at a guessed spot for a frame.
            .opacity(size == .zero ? 0 : 1)
            .position(placement.center)
            .zIndex(10)
            .accessibilityHidden(true)
    }
}
