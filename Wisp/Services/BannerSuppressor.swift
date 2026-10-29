import AppKit
import ApplicationServices

/// Closes the macOS notification banner once Wisp shows its own, through the
/// Accessibility API on the Notification Center process.
@MainActor
enum BannerSuppressor {
    private static let bundleID = "com.apple.notificationcenterui"

    /// Retries briefly, since the banner can appear a moment after the record lands.
    static func closeBanners() {
        guard AccessibilityPermission.isTrusted else { return }
        Task {
            for _ in 0..<6 {
                if closeVisibleBanners() { return }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private static func closeVisibleBanners() -> Bool {
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        else { return false }
        let app = AXUIElementCreateApplication(pid)
        var closed = false
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            closed = pressClose(in: window, depth: 0) || closed
        }
        return closed
    }

    /// Banners expose a "Close" action on one of their groups; find and press it.
    private static func pressClose(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 8 else { return false }
        var names: CFArray?
        if AXUIElementCopyActionNames(element, &names) == .success,
            let actions = names as? [String],
            let close = actions.first(where: { $0.contains("Close") })
        {
            return AXUIElementPerformAction(element, close as CFString) == .success
        }
        return children(of: element, attribute: kAXChildrenAttribute).contains { pressClose(in: $0, depth: depth + 1) }
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        // AX returns a CFArray of AXUIElement; bridging it is a checked conversion.
        return value as? [AXUIElement] ?? []
    }
}
