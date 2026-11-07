import AppKit
import CoreGraphics
import WispCore

/// Active mouse event tap that takes one extra mouse button (middle, back or forward) for
/// the ring. That button's events are swallowed so the app underneath never sees them;
/// every other button passes through. Needs Accessibility, like the keyboard tap.
@MainActor
final class MouseButtonTap {
    var onPress: @MainActor (CGPoint) -> Void = { _ in }
    var onMove: @MainActor (CGPoint) -> Void = { _ in }
    var onRelease: @MainActor (CGPoint) -> Void = { _ in }

    /// The CGEvent button number to take: 2 is the middle button, 3 back, 4 forward.
    private(set) var button: Int64 = 3
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    @discardableResult
    func start(button: Int64) -> Bool {
        self.button = button
        guard tap == nil else { return true }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: mouseTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Hands the event on to the ring when it's the ring's button; returns whether to swallow it.
    fileprivate func handle(_ type: CGEventType, button number: Int64) -> Bool {
        guard number == button else { return false }
        let location = NSEvent.mouseLocation
        let handler: @MainActor (CGPoint) -> Void
        switch type {
        case .otherMouseDown: handler = onPress
        case .otherMouseDragged: handler = onMove
        case .otherMouseUp: handler = onRelease
        default: return false
        }
        // Showing the ring can take a moment; doing it here could run the tap past its
        // timeout. The main queue keeps press, move and release in order.
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(location) } }
        return true
    }
}

private func mouseTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MouseButtonTap>.fromOpaque(refcon).takeUnretainedValue()
    // The run loop source is on the main run loop; only Sendable values cross over.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    let number = event.getIntegerValueField(.mouseEventButtonNumber)
    let swallow = MainActor.assumeIsolated { tap.handle(type, button: number) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
