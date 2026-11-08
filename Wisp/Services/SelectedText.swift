import AppKit
import ApplicationServices

/// Reads the text selected in another app through Accessibility. Password fields are skipped.
/// The calls block until the app answers, so they run off the main actor.
enum SelectedText {
    /// Short, so an app that doesn't answer can't hold up the ring for long.
    private static let timeout: Float = 0.25

    /// The selection in the focused element of the app `pid`, or nil when there's none or the
    /// element is a password field. The caller checks Accessibility first.
    static func read(from pid: pid_t) async -> String? {
        await Task.detached(priority: .userInitiated) { readNow(from: pid) }.value
    }

    private static func readNow(from pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let focused = element(of: app, attribute: kAXFocusedUIElementAttribute),
            string(of: focused, attribute: kAXSubroleAttribute) != kAXSecureTextFieldSubrole
        else { return nil }
        return string(of: focused, attribute: kAXSelectedTextAttribute)
    }

    /// Swift can't check a CF type with `as?`, so the type id is compared first; after that the
    /// downcast is exact.
    private static func element(of element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let found = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(found, timeout)
        return found
    }

    private static func string(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        // Selected text and subroles are CFStrings; the bridge checks the type.
        return value as? String
    }
}
