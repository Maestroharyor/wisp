import Carbon.HIToolbox
import WispCore

/// A standard global shortcut (no Caps Lock) via Carbon `RegisterEventHotKey`.
/// Needs no permission, which makes it the fallback when Accessibility is denied.
/// Each instance has its own id, so several can be registered at once.
@MainActor
final class CarbonHotkey {
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: @MainActor () -> Void = {}
    private var releaseAction: (@MainActor () -> Void)?

    nonisolated static let signature = OSType(0x5749_5350)  // "WISP"

    init(id: UInt32) {
        self.id = id
    }

    /// Returns false if the shortcut is invalid or already taken by another app. `onRelease`
    /// runs when the key comes back up.
    func register(
        _ hotkey: Hotkey, onRelease: (@MainActor () -> Void)? = nil, action: @escaping @MainActor () -> Void
    ) -> Bool {
        unregister()
        guard !hotkey.usesHyper else { return false }
        self.action = action
        self.releaseAction = onRelease

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard
            InstallEventHandler(
                GetApplicationEventTarget(), carbonHotkeyHandler, specs.count, &specs, userData, &handlerRef)
                == noErr
        else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode), Self.carbonModifiers(hotkey.modifiers), hotKeyID, GetApplicationEventTarget(), 0,
            &hotKeyRef)
        if status != noErr {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    /// Returns false when the event belongs to another instance's hotkey.
    fileprivate func fire(id: UInt32, released: Bool) -> Bool {
        guard id == self.id else { return false }
        if released {
            releaseAction?()
        } else {
            action()
        }
        return true
    }

    private static func carbonModifiers(_ modifiers: Hotkey.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}

private func carbonHotkeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr, hotKeyID.signature == CarbonHotkey.signature else { return OSStatus(eventNotHandledErr) }

    let hotkey = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
    // Carbon dispatches application events on the main thread.
    let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
    let handled = MainActor.assumeIsolated { hotkey.fire(id: hotKeyID.id, released: released) }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
