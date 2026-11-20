import AppKit
import ApplicationServices
import WispCore

/// Closes the macOS notification banner once Wisp shows its own, through the
/// Accessibility API on the Notification Center process. A banner asking to Accept or Decline
/// (an AirDrop request) is left alone whichever notification set this off.
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

    /// Banners expose a "Close" action on one of their groups; find and press it, unless that
    /// banner asks a question. Searching goes on past a banner that stays.
    private static func pressClose(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 8 else { return false }
        let actions = actionNames(of: element)
        if actions.contains(where: { BannerRule.title(of: $0).contains("Close") }) {
            let banner = actions + actionsBelow(element, depth: depth + 1)
            guard !BannerRule.keepsBanner(actions: banner), let close = BannerRule.closeAction(in: actions) else {
                return false
            }
            return AXUIElementPerformAction(element, close as CFString) == .success
        }
        return children(of: element, attribute: kAXChildrenAttribute).contains { pressClose(in: $0, depth: depth + 1) }
    }

    private static func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        // AX returns a CFArray of strings; bridging it is a checked conversion.
        return names as? [String] ?? []
    }

    /// Every action inside a banner, since its buttons can sit on children of the group that
    /// closes it.
    private static func actionsBelow(_ element: AXUIElement, depth: Int) -> [String] {
        guard depth < 8 else { return [] }
        return children(of: element, attribute: kAXChildrenAttribute).flatMap {
            actionNames(of: $0) + actionsBelow($0, depth: depth + 1)
        }
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        // AX returns a CFArray of AXUIElement; bridging it is a checked conversion.
        return value as? [AXUIElement] ?? []
    }
}
