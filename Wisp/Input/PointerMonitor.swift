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
