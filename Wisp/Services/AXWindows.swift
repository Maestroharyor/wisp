import AppKit
import ApplicationServices
import WispCore

/// Reading Accessibility trees, shared by the services that walk them.
enum AXTree {
    /// An array attribute's elements (windows, children, menus). Each gets `timeout` when one
    /// is given, since a timeout set on a parent doesn't carry over to its children.
    static func children(of element: AXUIElement, attribute: String, timeout: Float? = nil) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let list = value as? [AnyObject]
        else { return [] }
        return list.compactMap { axElement($0, timeout: timeout) }
    }

    /// Swift can't check a CF type with `as?`, so the type id is compared first; after that the
    /// downcast is exact.
    static func axElement(_ value: AnyObject, timeout: Float? = nil) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        if let timeout { AXUIElementSetMessagingTimeout(element, timeout) }
        return element
    }

    static func string(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        // Titles are CFStrings; the bridge checks the type.
        return value as? String
    }

    static func bool(of element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        // Flags such as AXMinimized are CFBooleans; the bridge checks the type.
        return value as? Bool
    }
}

/// An app's windows through Accessibility (already granted for the ring's mouse button and
/// pasting), read off the main thread with a short timeout so a busy app can't hold Wisp up.
/// Titles are shown in the ring and never logged or kept. Windows on other Spaces and in full
/// screen aren't listed, as Accessibility doesn't report them.
enum AXWindows {
    static let timeout: Float = 0.25
    /// The most a whole listing may take; a busy app with many windows gets cut short.
    static let deadline: TimeInterval = 1

    static func list(pid: pid_t) async -> [WindowSummary] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: summaries(of: windows(pid: pid)))
            }
        }
    }

    /// Brings the window forward, out of the Dock if it was minimised. False when it's gone.
    static func raise(pid: pid_t, target: AppWindows.Target) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let all = windows(pid: pid)
                guard let index = AppWindows.match(target, in: summaries(of: all)) else {
                    continuation.resume(returning: false)
                    return
                }
                let window = all[index]
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                continuation.resume(returning: true)
            }
        }
    }

    /// Standard windows only: an app's palettes, sheets and popovers aren't windows to switch to.
    private static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        let end = Date().addingTimeInterval(deadline)
        return AXTree.children(of: app, attribute: kAXWindowsAttribute, timeout: timeout).filter {
            Date() < end && AXTree.string(of: $0, attribute: kAXSubroleAttribute) == kAXStandardWindowSubrole
        }
    }

    private static func summaries(of windows: [AXUIElement]) -> [WindowSummary] {
        windows.map {
            WindowSummary(
                title: AXTree.string(of: $0, attribute: kAXTitleAttribute),
                isMinimised: AXTree.bool(of: $0, attribute: kAXMinimizedAttribute) ?? false)
        }
    }
}
