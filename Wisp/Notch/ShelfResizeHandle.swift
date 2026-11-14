import AppKit
import SwiftUI
import WispCore

/// The grabber on the open shelf's bottom edge. Dragging it makes the page taller or shorter;
/// double-clicking it goes back to the usual height.
struct ShelfResizeHandle: View {
    let model: NotchModel

    /// The area that takes the drag, centred on the edge. It reaches no further past the
    /// edge than the shelf's hover margin, so a press there never counts as a click outside;
    /// inside, it stays in the bottom inset, clear of the page and the approval bar.
    static let size = CGSize(width: 140, height: 12)
    /// How far the area's centre sits inside the edge.
    static let inset: CGFloat = 1

    @State private var hovering = false
    @State private var dragStart: CGFloat?

    var body: some View {
        let active = hovering || dragStart != nil
        Capsule()
            .fill(.white.opacity(active ? 0.7 : 0.22))
            .frame(width: 40, height: 4)
            .animation(.easeOut(duration: 0.15), value: active)
            .frame(width: Self.size.width, height: Self.size.height)
            .contentShape(Rectangle())
            .background(ResizeCursorArea(dragging: dragStart != nil).allowsHitTesting(false))
            .onHover { hovering = $0 }
            .gesture(
                // Window coordinates: the panel never moves, while this view rides the edge. A few
                // points before it starts, so a double-click's jitter doesn't count as a drag.
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? model.shelfExtra
                        if dragStart == nil { dragStart = start }
                        model.resizeShelf(from: start, by: value.translation.height)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        model.endShelfResize()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetShelfHeight() })
            .onDisappear {
                if dragStart != nil { model.endShelfResize() }
                dragStart = nil
                hovering = false
            }
            .help("Drag to resize, double-click to reset")
            .accessibilityElement()
            .accessibilityLabel("Shelf height")
            .accessibilityHint("Drag to make the shelf taller or shorter. Double-click to reset.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.nudgeShelfHeight(by: Self.accessibilityStep)
                case .decrement: model.nudgeShelfHeight(by: -Self.accessibilityStep)
                @unknown default: break
                }
            }
    }

    private static let accessibilityStep: CGFloat = 40
}

/// The up-down cursor over the handle and through a drag of it. The panel doesn't activate
/// Wisp, and with another app in front a cursor pushed from SwiftUI's hover doesn't reliably
/// show, so an always-active tracking area sets it on every enter, move and cursor update.
private struct ResizeCursorArea: NSViewRepresentable {
    let dragging: Bool

    func makeNSView(context: Context) -> ResizeCursorView { ResizeCursorView() }

    func updateNSView(_ view: ResizeCursorView, context: Context) {
        view.dragging = dragging
    }
}

private final class ResizeCursorView: NSView {
    private var inside = false

    var dragging = false {
        didSet {
            guard dragging != oldValue else { return }
            if dragging || inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
    }

    /// Clicks go to the SwiftUI handle underneath; tracking doesn't need them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) {
        inside = true
        NSCursor.resizeUpDown.set()
    }

    override func mouseMoved(with event: NSEvent) {
        if inside || dragging { NSCursor.resizeUpDown.set() }
    }

    override func mouseExited(with event: NSEvent) {
        inside = false
        if !dragging { NSCursor.arrow.set() }
    }

    /// The shelf closing under the pointer mustn't leave the up-down cursor behind.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, inside || dragging else { return }
        inside = false
        NSCursor.arrow.set()
    }
}
