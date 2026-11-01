import AppKit
import SwiftUI
import WispCore

/// Click, then press a shortcut. Needs ⌃, ⌥ or ⌘ (⇧ alone only on a function key); Esc cancels.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    @State private var recording = false
    /// Set when a key was pressed with only Shift, so the button can say why nothing happened.
    @State private var needsModifier = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? (needsModifier ? "Add ⌃, ⌥ or ⌘…" : "Press a shortcut…") : hotkey.description) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = Self.modifiers(from: event.modifierFlags)
            MainActor.assumeIsolated {
                if keyCode == KeyCodes.escape {
                    stop()
                } else if !modifiers.isEmpty, Hotkey(keyCode: keyCode, modifiers: modifiers).isUsable {
                    hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
                    stop()
                } else if modifiers == .shift {
                    needsModifier = true
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        needsModifier = false
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Hotkey.Modifiers {
        var modifiers: Hotkey.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
