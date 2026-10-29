import AppKit
import ApplicationServices

/// Accessibility (TCC) access, needed for the Caps Lock event tap.
/// The grant is tied to the code signature, hence the stable "Wisp Dev" certificate.
@MainActor
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Wisp to the Accessibility list.
    static func requestAccess() {
        // Value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Polls until access is granted or the task is cancelled.
    static func waitUntilTrusted() async {
        while !AXIsProcessTrusted(), !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
