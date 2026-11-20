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
            guard let close = BannerRule.closeAction(in: actions, labels: labelsBelow(element, levels: 6)) else {
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

    /// Everything inside a banner that could name an answer: its parts' actions, and its
    /// buttons' titles and descriptions, since Accept can be a button whose only action is
    /// a plain press. `levels` counts down from the banner, wherever it sits in the tree.
    private static func labelsBelow(_ element: AXUIElement, levels: Int) -> [String] {
        guard levels > 0 else { return [] }
        return children(of: element, attribute: kAXChildrenAttribute).flatMap {
            actionNames(of: $0)
                + [text(of: $0, kAXTitleAttribute), text(of: $0, kAXDescriptionAttribute)].compactMap(\.self)
                + labelsBelow($0, levels: levels - 1)
        }
    }

    private static func text(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        // Titles and descriptions are CFStrings; bridging one is a checked conversion.
        return value as? String
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        AXTree.children(of: element, attribute: attribute)
    }
}
