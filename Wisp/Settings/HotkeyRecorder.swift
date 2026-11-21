import AppKit
import SwiftUI
import WispCore

/// Click, then press a shortcut. Needs ⌃, ⌥ or ⌘ (⇧ alone only on a function key), or Caps Lock
/// while it's Wisp's Hyper key; Esc cancels. A key something else already uses is refused,
/// and the button says what uses it.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    /// Records Caps Lock chords through the Hyper tap, which otherwise swallows them.
    var hotkeys: HotkeyCenter?
    /// What already uses a key, if anything.
    var clash: (Hotkey) -> String? = { _ in nil }
    @State private var recording = false
    /// Set when a key was pressed with only Shift, so the button can say why nothing happened.
    @State private var needsModifier = false
    /// The last key refused, and what uses it.
    @State private var refused: String?
    @State private var monitor: Any?

    var body: some View {
        Button(label) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
        .accessibilityHint(recording ? "Press the keys for the new shortcut, or Escape to cancel" : "")
    }

    private var label: String {
        guard recording else { return hotkey.description }
        if let refused { return "Used by \(refused)" }
        return needsModifier ? "Add ⌃, ⌥ or ⌘…" : "Press a shortcut…"
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
                    offer(Hotkey(keyCode: keyCode, modifiers: modifiers))
                } else if modifiers == .shift {
                    needsModifier = true
                }
            }
            return nil
        }
        hotkeys?.captureHyperChord = { keyCode in
            offer(Hotkey(keyCode: keyCode, modifiers: .hyper))
        }
    }

    private func offer(_ candidate: Hotkey) {
        if let user = clash(candidate) {
            refused = user
            needsModifier = false
            return
        }
        hotkey = candidate
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotkeys?.captureHyperChord = nil
        recording = false
        needsModifier = false
        refused = nil
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
