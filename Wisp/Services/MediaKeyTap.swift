import AppKit
import CoreGraphics
import WispCore

/// Active event tap on system-defined events (volume, brightness, mute keys).
/// The handler returns true to swallow a key, which also suppresses the system overlay.
/// Needs Accessibility.
@MainActor
final class MediaKeyTap {
    var handler: (MediaKeyEvent, _ fine: Bool) -> Bool = { _, _ in false }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// NX_SYSDEFINED; CGEventType has no case for it.
    nonisolated static let systemDefinedType: UInt32 = 14

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << Self.systemDefinedType)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: mediaKeyTapCallback,
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
}

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == MediaKeyTap.systemDefinedType,
        let nsEvent = NSEvent(cgEvent: event),
        nsEvent.subtype.rawValue == 8,
        let decoded = MediaKeyEvent(data1: nsEvent.data1)
    else { return Unmanaged.passUnretained(event) }

    let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
    // The tap's run loop source is on the main run loop; only Sendable values cross over.
    let swallow = MainActor.assumeIsolated { tap.handler(decoded, fine) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
