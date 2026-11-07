import AppKit
import SwiftUI

/// A dimmed overlay on every screen to drag a rectangle over part of a window. Esc, a
/// right click or a click without a drag cancels.
@MainActor
final class RegionPicker {
    private var panels: [RegionPickerPanel] = []
    private var completion: ((CGRect?) -> Void)?

    var isPicking: Bool { !panels.isEmpty }

    /// Calls back with the rectangle in AppKit global coordinates, or nil when cancelled.
    func pick(_ completion: @escaping (CGRect?) -> Void) {
        finish(nil)
        self.completion = completion
        panels = NSScreen.screens.map { screen in
            let panel = RegionPickerPanel(frame: screen.frame)
            let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self, weak panel] rect in
                guard let panel else { return }
                self?.finish(rect.map { panel.convertToScreen($0) })
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            return panel
        }
        let mouse = NSEvent.mouseLocation
        let active = panels.first { $0.frame.contains(mouse) } ?? panels.first
        active?.makeKey()
        active?.makeFirstResponder(active?.contentView)
    }

    private func finish(_ rect: CGRect?) {
        let done = completion
        completion = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        done?(rect)
    }
}

/// Borderless, key-capable and non-activating, so the app being watched stays in front.
private final class RegionPickerPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the dim layer with the selection cut out of it and reports the finished drag.
private final class RegionSelectionView: NSView {
    var onFinish: (CGRect?) -> Void = { _ in }
    private var origin: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        origin = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x),
            height: abs(point.y - origin.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= 8, selection.height >= 8 else {
            onFinish(nil)
            return
        }
        onFinish(selection)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            NSColor(Color.wispViolet).setStroke()
            border.stroke()
        }
        drawHint()
    }

    private func drawHint() {
        let text = NSAttributedString(
            string: "Drag over the part of a window to watch. Esc cancels.",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white])
        let size = text.size()
        let box = CGRect(
            x: bounds.midX - size.width / 2 - 14, y: bounds.maxY - 120, width: size.width + 28,
            height: size.height + 14)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: CGPoint(x: box.minX + 14, y: box.minY + 7))
    }
}
