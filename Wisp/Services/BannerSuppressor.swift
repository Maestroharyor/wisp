import AppKit
import ApplicationServices
import WispCore

/// Closes the macOS notification banner once Wisp shows its own, through the
/// Accessibility API on the Notification Center process. A banner asking to Accept or Decline
/// (an AirDrop request) is left alone whichever notification set this off.
///
/// Accessibility calls block until Notification Center answers, so the search runs off the main
/// actor (where the key taps live) and every element gets a short messaging timeout.
enum BannerSuppressor {
    private static let bundleID = "com.apple.notificationcenterui"
    private static let timeout: Float = 0.25

    /// Closes the banner showing this title and body, retrying briefly, since the banner can
    /// appear a moment after the record lands. Other apps' banners are left alone.
    @MainActor
    static func closeBanner(title: String, body: String) {
        guard AccessibilityPermission.isTrusted else { return }
        Task.detached(priority: .utility) {
            for _ in 0..<6 {
                if closeVisibleBanner(title: title, body: body) { return }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private static func closeVisibleBanner(title: String, body: String) -> Bool {
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return children(of: app, attribute: kAXWindowsAttribute).contains {
            pressClose(in: $0, title: title, body: body, depth: 0)
        }
    }

    /// Banners expose a "Close" action on one of their groups; find and press it on the banner
    /// for this card, unless that banner asks a question. Searching goes on past one that stays.
    private static func pressClose(in element: AXUIElement, title: String, body: String, depth: Int) -> Bool {
        guard depth < 8 else { return false }
        let actions = actionNames(of: element)
        if actions.contains(where: { BannerRule.title(of: $0).contains("Close") }) {
            let texts = textsBelow(element, levels: 6) + [text(of: element, kAXDescriptionAttribute)].compactMap(\.self)
            guard BannerRule.shows(texts: texts, title: title, body: body),
                let close = BannerRule.closeAction(in: actions, labels: labelsBelow(element, levels: 6) + texts)
            else { return false }
            return AXUIElementPerformAction(element, close as CFString) == .success
        }
        return children(of: element, attribute: kAXChildrenAttribute).contains {
            pressClose(in: $0, title: title, body: body, depth: depth + 1)
        }
    }

    /// The words a banner shows: its text's values and descriptions. Read only to compare with
    /// the card, never kept or logged.
    private static func textsBelow(_ element: AXUIElement, levels: Int) -> [String] {
        guard levels > 0 else { return [] }
        return children(of: element, attribute: kAXChildrenAttribute).flatMap {
            [text(of: $0, kAXValueAttribute), text(of: $0, kAXDescriptionAttribute)].compactMap(\.self)
                + textsBelow($0, levels: levels - 1)
        }
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
        AXTree.children(of: element, attribute: attribute, timeout: timeout)
    }
}
