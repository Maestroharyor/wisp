import AppKit
import ApplicationServices
import OSLog
import Observation
import WispCore

/// Drives the call app's own mute, camera, share and leave through Accessibility: Zoom by
/// pressing its menu bar items, Teams and Meet (in a Chromium browser, opt-in) by bringing the
/// call forward and typing their documented shortcuts. Shows nothing for anything else.
/// Accessibility calls block until the other app answers, so they run off the main actor with
/// a short timeout and only the results come back here.
@MainActor
@Observable
final class MeetingControlsDriver {
    private(set) var app: MeetingApp?
    private(set) var states: [MeetingControlState] = []
    /// A press is in flight; further taps wait for it.
    private(set) var isPerforming = false
    /// Teams and Meet are typed into, so they're a separate opt-in (Preferences).
    @ObservationIgnored var allowsShortcutApps = false

    @ObservationIgnored private var inputApps: [String] = []
    /// Which menu bar menu holds Zoom's call items, so later reads open only that one.
    @ObservationIgnored private var zoomMenuIndex: Int?
    @ObservationIgnored private var reading = false
    /// A refresh asked for while one was running or a press was in flight; it runs after.
    @ObservationIgnored private var refreshQueued = false
    /// Bumped by `clear` and each press, so a reading that started before either is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "meeting-controls")

    /// Works out which app to drive and reads its controls in the background.
    func refresh(inputApps: [String]) {
        self.inputApps = inputApps
        guard AccessibilityPermission.isTrusted else {
            clear()
            return
        }
        guard !reading, !isPerforming else {
            refreshQueued = true
            return
        }
        reading = true
        refreshQueued = false
        let started = generation
        let request = AXProbe.Request(
            inputApps: inputApps, pids: Self.candidatePIDs(), allowsShortcutApps: allowsShortcutApps,
            zoomMenuIndex: zoomMenuIndex)
        Task {
            let reading = await Task.detached { AXProbe.read(request) }.value
            self.reading = false
            if started == generation, let reading { apply(reading) }
            runQueuedRefresh()
        }
    }

    func clear() {
        generation += 1
        refreshQueued = false
        if app != nil { app = nil }
        if !states.isEmpty { states = [] }
    }

    func perform(_ control: MeetingControl) {
        guard !isPerforming, AccessibilityPermission.isTrusted, let app,
            MeetingControls.strategy(for: control, in: app) != nil,
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?
                .processIdentifier
        else { return }
        isPerforming = true
        generation += 1
        let press = AXProbe.Press(
            control: control, app: app, pid: pid,
            previousPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, zoomMenuIndex: zoomMenuIndex)
        Task {
            let sent = await Task.detached { await AXProbe.perform(press) }.value
            if !sent { log.info("Meeting control \(control.rawValue, privacy: .public) wasn't sent") }
            isPerforming = false
            refresh(inputApps: inputApps)
        }
    }

    private func runQueuedRefresh() {
        guard refreshQueued, !isPerforming else { return }
        refresh(inputApps: inputApps)
    }

    private func apply(_ reading: AXProbe.Reading) {
        zoomMenuIndex = reading.zoomMenuIndex
        if app != reading.app { app = reading.app }
        if states != reading.states { states = reading.states }
    }

    /// Process ids of the apps that could be driven, looked up here since NSRunningApplication
    /// belongs on the main thread.
    private static func candidatePIDs() -> [String: pid_t] {
        var pids: [String: pid_t] = [:]
        for id in [MeetingApp.zoom.bundleID, MeetingApp.teams.bundleID] + MeetingControls.meetBrowsers {
            if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.processIdentifier {
                pids[id] = pid
            }
        }
        return pids
    }
}

/// The Accessibility work, away from the main actor. A messaging timeout applies only to the
/// element it's set on, so every element the helpers hand out gets the short one, and each read
/// or press also stops at an overall deadline, so a hung call app can't hold Wisp up.
enum AXProbe {
    struct Request: Sendable {
        let inputApps: [String]
        let pids: [String: pid_t]
        let allowsShortcutApps: Bool
        let zoomMenuIndex: Int?
    }

    struct Reading: Sendable {
        let app: MeetingApp?
        let states: [MeetingControlState]
        let zoomMenuIndex: Int?
    }

    struct Press: Sendable {
        let control: MeetingControl
        let app: MeetingApp
        let pid: pid_t
        let previousPID: pid_t?
        let zoomMenuIndex: Int?
    }

    static let timeout: Float = 0.25
    /// The most a whole read or press may take before it gives up.
    static let deadline: TimeInterval = 2

    /// Nil when the deadline passed, so the last good reading stays.
    static func read(_ request: Request) -> Reading? {
        let end = Date().addingTimeInterval(deadline)
        var meetWindows: Set<String> = []
        for browser in MeetingControls.meetBrowsers {
            guard let pid = request.pids[browser],
                request.inputApps.contains(where: { $0 == browser || $0.hasPrefix(browser + ".") })
            else { continue }
            if meetWindow(in: application(pid)) != nil { meetWindows.insert(browser) }
            if Date() > end { return nil }
        }
        guard let app = MeetingControls.app(inputApps: request.inputApps, meetWindows: meetWindows),
            request.allowsShortcutApps || !MeetingControls.usesShortcuts(app),
            let pid = request.pids[app.bundleID]
        else { return Reading(app: nil, states: [], zoomMenuIndex: request.zoomMenuIndex) }
        guard MeetingControls.usesMenu(app) else {
            return Reading(app: app, states: MeetingControls.states(for: app, menuTitles: []), zoomMenuIndex: nil)
        }
        let menu = callMenu(of: application(pid), app: app, cached: request.zoomMenuIndex)
        guard Date() <= end else { return nil }
        return Reading(
            app: app, states: MeetingControls.states(for: app, menuTitles: menu.items.map(\.title)),
            zoomMenuIndex: menu.index)
    }

    /// Sends one control. Returns whether it went through. Nothing is sent past the deadline.
    /// Once focus has moved, it is handed back on every path (see `MeetingControls.handBack`).
    static func perform(_ press: Press) async -> Bool {
        let end = Date().addingTimeInterval(deadline)
        let target = application(press.pid)
        let previousWindow = press.previousPID == press.pid ? focusedWindow(of: target).flatMap(title) : nil
        var movedFocus = false
        var sent = false
        if MeetingControls.bringsForward(press.app, for: press.control) {
            movedFocus = true
            if await bringForward(press.app, target: target), Date() <= end {
                sent = send(press, target: target, end: end)
            }
        } else {
            sent = send(press, target: target, end: end)
        }
        let callWindow = focusedWindow(of: target).flatMap(title)
        let back = MeetingControls.handBack(
            movedFocus: movedFocus, sent: sent, control: press.control, previousPID: press.previousPID,
            targetPID: press.pid, previousWindow: previousWindow, callWindow: callWindow)
        if sent { try? await Task.sleep(for: .milliseconds(150)) }
        switch back {
        case .none: break
        case .app(let pid): setFrontmost(application(pid))
        case .window(let name):
            if let window = windows(of: target).first(where: { title($0) == name }) { raise(window) }
        }
        return sent
    }

    private static func send(_ press: Press, target: AXUIElement, end: Date) -> Bool {
        switch MeetingControls.strategy(for: press.control, in: press.app) {
        case .menu:
            let menu = callMenu(of: target, app: press.app, cached: press.zoomMenuIndex)
            guard Date() <= end,
                let item = menu.items.first(where: {
                    MeetingControls.menuItem($0.title, drives: press.control, in: press.app)
                })
            else { return false }
            return AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
        case .shortcut(let shortcut):
            // Checked right before typing, so the keys can only land in the call: a fresh
            // snapshot, then frontmost read once more as the very last step.
            guard Date() <= end, MeetingControls.mayType(press.app, focus: snapshot(of: target)),
                bool(of: target, attribute: kAXFrontmostAttribute) == true
            else { return false }
            type(shortcut)
            return true
        case nil:
            return false
        }
    }

    // MARK: Menus

    private struct MenuItem {
        let title: String
        let element: AXUIElement
    }

    /// The enabled items of the menu bar menu holding the app's call items. The cached menu is
    /// read alone; the whole bar is searched only when that misses.
    private static func callMenu(of app: AXUIElement, app call: MeetingApp, cached: Int?) -> (
        index: Int?, items: [MenuItem]
    ) {
        let barItems = menuBarItems(of: app)
        func holdsCall(_ items: [MenuItem]) -> Bool {
            items.contains { item in
                MeetingControl.allCases.contains { MeetingControls.menuItem(item.title, drives: $0, in: call) }
            }
        }
        if let cached, barItems.indices.contains(cached) {
            let items = menuItems(under: barItems[cached])
            if holdsCall(items) { return (cached, items) }
        }
        for (index, barItem) in barItems.enumerated() where index != cached {
            let items = menuItems(under: barItem)
            if holdsCall(items) { return (index, items) }
        }
        return (nil, [])
    }

    private static func menuBarItems(of app: AXUIElement) -> [AXUIElement] {
        children(of: app, attribute: kAXChildrenAttribute)
            .filter { string(of: $0, attribute: kAXRoleAttribute) == kAXMenuBarRole }
            .flatMap { children(of: $0, attribute: kAXChildrenAttribute) }
    }

    /// One level deep: Zoom's call items sit directly in their menu.
    private static func menuItems(under barItem: AXUIElement) -> [MenuItem] {
        children(of: barItem, attribute: kAXChildrenAttribute).flatMap { menu in
            children(of: menu, attribute: kAXChildrenAttribute).compactMap { item in
                guard bool(of: item, attribute: kAXEnabledAttribute) != false,
                    let title = string(of: item, attribute: kAXTitleAttribute), !title.isEmpty
                else { return nil }
                return MenuItem(title: title, element: item)
            }
        }
    }

    // MARK: Focus

    private static func meetWindow(in app: AXUIElement) -> AXUIElement? {
        windows(of: app).first(where: isMeetWindow)
    }

    private static func isMeetWindow(_ window: AXUIElement) -> Bool {
        MeetingControls.isMeetWindow(title: title(window), url: string(of: window, attribute: kAXDocumentAttribute))
    }

    /// Raises the call's window and makes its app frontmost, then waits for it to be.
    private static func bringForward(_ call: MeetingApp, target: AXUIElement) async -> Bool {
        if case .meet = call {
            guard let window = meetWindow(in: target) else { return false }
            raise(window)
        }
        setFrontmost(target)
        for _ in 0..<10 {
            if bool(of: target, attribute: kAXFrontmostAttribute) == true { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Timed, so a slow read (which may describe a window that has since changed) isn't typed on.
    private static func snapshot(of app: AXUIElement) -> FocusSnapshot {
        let started = Date()
        let window = focusedWindow(of: app)
        let focused = element(of: app, attribute: kAXFocusedUIElementAttribute)
        var snapshot = FocusSnapshot(
            appIsFrontmost: bool(of: app, attribute: kAXFrontmostAttribute) == true,
            windowTitle: window.flatMap(title),
            windowURL: window.flatMap { string(of: $0, attribute: kAXDocumentAttribute) },
            hasFocusedWindow: window != nil,
            focusedRole: focused.flatMap { string(of: $0, attribute: kAXRoleAttribute) },
            focusedInWebArea: focused.map(isInWebArea) ?? false)
        snapshot.readSeconds = Date().timeIntervalSince(started)
        return snapshot
    }

    /// Whether an element sits inside a page rather than in the browser's own toolbar.
    private static func isInWebArea(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let node = current else { return false }
            if string(of: node, attribute: kAXRoleAttribute) == "AXWebArea" { return true }
            current = self.element(of: node, attribute: kAXParentAttribute)
        }
        return false
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        element(of: app, attribute: kAXFocusedWindowAttribute)
    }

    private static func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func setFrontmost(_ app: AXUIElement) {
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func type(_ shortcut: KeyShortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        if shortcut.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if shortcut.modifiers.contains(.shift) { flags.insert(.maskShift) }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: down)
            else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: AX helpers

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        children(of: app, attribute: kAXWindowsAttribute)
    }

    private static func title(_ element: AXUIElement) -> String? {
        string(of: element, attribute: kAXTitleAttribute)
    }

    /// An array attribute's elements (windows, menus, items). Bridging the CFArray to
    /// `[AnyObject]` is checked; each entry then goes through `axElement`.
    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let list = value as? [AnyObject]
        else { return [] }
        return list.compactMap(axElement)
    }

    /// A single element attribute (focused window, focused element, parent).
    private static func element(of element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else {
            return nil
        }
        return axElement(value)
    }

    /// Swift can't check a CF type with `as?`, so the type id is compared first; after that the
    /// downcast is exact. Every element handed out gets the short messaging timeout, since a
    /// timeout set on the application element doesn't carry over to its children.
    private static func axElement(_ value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    private static func string(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        // Titles, roles and documents are CFStrings; the bridge checks the type.
        return value as? String
    }

    private static func bool(of element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        // Flags such as AXEnabled are CFBooleans; the bridge checks the type.
        return value as? Bool
    }
}
