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

    nonisolated static let signature = OSType(0x5749_5350)  // "WISP"

    init(id: UInt32) {
        self.id = id
    }

    /// Returns false if the shortcut is invalid or already taken by another app.
    func register(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        guard !hotkey.usesHyper else { return false }
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard
            InstallEventHandler(GetApplicationEventTarget(), carbonHotkeyHandler, 1, &spec, userData, &handlerRef)
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
    fileprivate func fire(id: UInt32) -> Bool {
        guard id == self.id else { return false }
        action()
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
    let handled = MainActor.assumeIsolated { hotkey.fire(id: hotKeyID.id) }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
