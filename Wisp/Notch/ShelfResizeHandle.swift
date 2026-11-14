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
    @State private var cursorPushed = false

    var body: some View {
        let active = hovering || dragStart != nil
        Capsule()
            .fill(.white.opacity(active ? 0.7 : 0.22))
            .frame(width: 40, height: 4)
            .animation(.easeOut(duration: 0.15), value: active)
            .frame(width: Self.size.width, height: Self.size.height)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                updateCursor()
            }
            .gesture(
                // Window coordinates: the panel never moves, while this view rides the edge. A few
                // points before it starts, so a double-click's jitter doesn't count as a drag.
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? model.shelfExtra
                        if dragStart == nil {
                            dragStart = start
                            updateCursor()
                        }
                        model.resizeShelf(from: start, by: value.translation.height)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        model.endShelfResize()
                        updateCursor()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetShelfHeight() })
            .onDisappear {
                if dragStart != nil { model.endShelfResize() }
                dragStart = nil
                hovering = false
                updateCursor()
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

    /// The up-down cursor while the pointer is on the handle or dragging it, pushed once and
    /// popped once so other cursors stay balanced.
    private func updateCursor() {
        let wanted = hovering || dragStart != nil
        guard wanted != cursorPushed else { return }
        if wanted {
            NSCursor.resizeUpDown.push()
        } else {
            NSCursor.pop()
        }
        cursorPushed = wanted
    }
}
