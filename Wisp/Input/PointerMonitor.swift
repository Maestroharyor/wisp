import AppKit

/// Reports pointer movement, clicks and drags anywhere on screen. Global monitors
/// cover other apps; local monitors cover Wisp's own panels. Mouse monitoring needs
/// no permission (only key monitoring does).
@MainActor
final class PointerMonitor {
    enum Action {
        case moved
        case leftDown
        case rightDown
        case dragged
        case leftUp
    }

    private var monitors: [Any] = []

    func start(_ handler: @escaping @MainActor (Action, CGPoint) -> Void) {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .leftMouseUp,
        ]

        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            let action = Self.action(for: event.type)
            MainActor.assumeIsolated { handler(action, NSEvent.mouseLocation) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            let action = Self.action(for: event.type)
            MainActor.assumeIsolated { handler(action, NSEvent.mouseLocation) }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    /// A trackpad scroll step in finger terms: dx is positive when fingers move right, dy
    /// positive when they move up, whatever the natural scrolling setting.
    struct Scroll {
        var dx: Double
        var dy: Double
        /// A new gesture began, or the last one ended.
        var boundary: Bool
    }

    /// Two-finger trackpad scrolls only; mouse wheels and momentum are ignored.
    func startScroll(_ handler: @escaping @MainActor (Scroll, CGPoint) -> Void) {
        let report: (NSEvent) -> Void = { event in
            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
            let inverted = event.isDirectionInvertedFromDevice
            let scroll = Scroll(
                dx: inverted ? event.scrollingDeltaX : -event.scrollingDeltaX,
                dy: inverted ? -event.scrollingDeltaY : event.scrollingDeltaY,
                boundary: !event.phase.isDisjoint(with: [.began, .ended, .cancelled]))
            MainActor.assumeIsolated { handler(scroll, NSEvent.mouseLocation) }
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: report)
        let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            report(event)
            return event
        }
        monitors += [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private nonisolated static func action(for type: NSEvent.EventType) -> Action {
        switch type {
        case .leftMouseDown: .leftDown
        case .rightMouseDown: .rightDown
        case .leftMouseDragged: .dragged
        case .leftMouseUp: .leftUp
        default: .moved
        }
    }
}
