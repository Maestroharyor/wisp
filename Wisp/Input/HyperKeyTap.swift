import CoreGraphics
import Foundation
import WispCore

/// Active keyboard event tap that turns the remapped Caps Lock (F18) into a Hyper
/// modifier. Hyper chords are swallowed so the key never types. Needs Accessibility.
@MainActor
final class HyperKeyTap {
    /// Called for each key pressed while Hyper is held. Return true to swallow it.
    var onHyperChord: (UInt16) -> Bool = { _ in false }
    var quickPressTogglesCapsLock = true

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hyperDown = false
    private var chordUsed = false
    private var swallowedKeyUps: Set<UInt16> = []

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hyperTapCallback,
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
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        hyperDown = false
        swallowedKeyUps.removeAll()
    }

    fileprivate func reenable() {
        // macOS disables slow or interrupted taps; turn it straight back on.
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Decides whether a key event is swallowed (true) or passed on (false).
    fileprivate func shouldSwallow(keyCode: UInt16, isKeyDown: Bool) -> Bool {
        if keyCode == KeyCodes.f18 {
            if isKeyDown, !hyperDown {
                hyperDown = true
                chordUsed = false
            } else if !isKeyDown {
                hyperDown = false
                if !chordUsed, quickPressTogglesCapsLock {
                    CapsLockState.toggle()
                }
            }
            return true
        }

        if !isKeyDown, swallowedKeyUps.remove(keyCode) != nil {
            return true
        }

        if isKeyDown, hyperDown {
            chordUsed = true
            if onHyperChord(keyCode) {
                swallowedKeyUps.insert(keyCode)
                return true
            }
        }
        return false
    }
}

private func hyperTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HyperKeyTap>.fromOpaque(refcon).takeUnretainedValue()

    // The tap's run loop source is on the main run loop (see start()). Only Sendable
    // values cross into the main actor; the event itself stays here.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let isKeyDown = type == .keyDown
    let swallow = MainActor.assumeIsolated { tap.shouldSwallow(keyCode: keyCode, isKeyDown: isKeyDown) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
