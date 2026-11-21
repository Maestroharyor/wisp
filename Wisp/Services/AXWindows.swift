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
                continuation.resume(returning: read(pid: pid).summaries)
            }
        }
    }

    /// Brings the window forward, out of the Dock if it was minimised. False when it's gone, or
    /// when an untitled window can't be told apart because the app answered too slowly.
    static func raise(pid: pid_t, target: AppWindows.Target) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let found = read(pid: pid)
                // Untitled windows are matched by place, which a cut-short list doesn't know.
                guard found.complete || target.title != nil,
                    let index = AppWindows.match(target, in: found.summaries)
                else {
                    continuation.resume(returning: false)
                    return
                }
                let window = found.windows[index]
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                continuation.resume(returning: true)
            }
        }
    }

    private struct Reading {
        var windows: [AXUIElement] = []
        var summaries: [WindowSummary] = []
        /// False when the deadline cut the reading short.
        var complete = true
    }

    /// Standard windows only: an app's palettes, sheets and popovers aren't windows to switch
    /// to. One deadline covers the whole reading, so a busy app with many windows can't take
    /// much longer than it.
    private static func read(pid: pid_t) -> Reading {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        let end = Date().addingTimeInterval(deadline)
        var reading = Reading()
        for window in AXTree.children(of: app, attribute: kAXWindowsAttribute, timeout: timeout) {
            guard Date() < end else {
                reading.complete = false
                break
            }
            guard AXTree.string(of: window, attribute: kAXSubroleAttribute) == kAXStandardWindowSubrole else {
                continue
            }
            reading.windows.append(window)
            reading.summaries.append(
                WindowSummary(
                    title: AXTree.string(of: window, attribute: kAXTitleAttribute),
                    isMinimised: AXTree.bool(of: window, attribute: kAXMinimizedAttribute) ?? false))
        }
        return reading
    }
}
