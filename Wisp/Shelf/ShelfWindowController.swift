import AppKit
import SwiftUI
import WispCore

/// The shelf's pages in an ordinary titled window, for using Wisp like any other app.
/// Minimising or closing it puts Wisp back into the form it had (notch, island, orb); the
/// rules for what opens where are `ShelfWindowState`.
@MainActor
final class ShelfWindowController: NSObject, NSWindowDelegate {
    private let services: AppServices
    private var window: ShelfWindow?
    private var model: NotchModel?
    private var isOpen = false
    /// Fading out; a show meanwhile cancels the pending orderOut.
    private var hiding = false
    /// Moving the window ourselves, so its frame isn't saved mid-animation.
    private var animating = false
    /// Where the pointer holds a window being torn off, relative to its origin.
    private var tearAnchor: CGVector?
    /// The window's ⌘ keys, installed while it's on screen.
    private var keyMonitor: Any?
    private var motionObserver: NSObjectProtocol?
    /// Set by the notch coordinator: the closed shell nearest a frame, which the window
    /// leaves toward and comes back out of.
    var shellRect: @MainActor (CGRect) -> CGRect? = { _ in nil }

    /// The sidebar's selection, which pills, menus and tearing off point at a row.
    private let navigation: WindowNavigation

    init(services: AppServices) {
        self.services = services
        navigation = WindowNavigation(preferences: services.preferences)
        super.init()
        // Reduce Motion switched on while the window shows takes effect on its pages right away,
        // as it does on the notch, rather than at the next open.
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    private var preferences: Preferences { services.preferences }

    /// Built fresh each time so the Window form always follows Settings.
    private var state: ShelfWindowState {
        ShelfWindowState(windowForm: preferences.windowForm, isOpen: isOpen)
    }

    var opensUnderShell: Bool { state.opensUnderShell }

    /// The form to show as current for a display whose shell has `shell`'s form.
    func form(shell: FormFactor) -> FormFactor { state.form(shell: shell) }

    /// Takes the window off screen for a screenshot or colour pick, so it isn't in the way; the
    /// returned closure brings it back unless it was put away meanwhile.
    func stepAside() -> @MainActor @Sendable () -> Void {
        guard let window, window.isVisible, !hiding else { return {} }
        let wasKey = window.isKeyWindow
        window.orderOut(nil)
        return { [weak self] in
            guard let self, self.isOpen, !self.hiding, let window = self.window else { return }
            if wasKey {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFront(nil)
            }
        }
    }

    /// "Open as Window" from the menu, on what the shelf shows.
    func openAsWindow(view: ShelfView) {
        prepare(view)
        run(.openAsWindow)
    }

    /// The shell was clicked, swiped or asked for a page while the window has the shelf.
    /// `view` is what to open on, if anything: a page, a widget, or a clicked pill's own view.
    func activateShell(view: ShelfView? = nil, session: String? = nil) {
        prepare(view, session: session)
        run(.activateShell)
    }

    /// The open-or-close shortcut while the window has the shelf.
    func toggle() {
        run(.toggle(windowInFront: window.map { $0.isVisible && $0.isKeyWindow && NSApp.isActive } ?? false))
    }

    /// A form from any switcher. `applyShell` switches the display's shell to a shell form.
    func pick(_ form: FormFactor, applyShell: @escaping @MainActor (FormFactor) -> Void) {
        run(.pick(form), applyShell: applyShell)
    }

    /// The Window form switched in Settings.
    func setWindowForm(_ on: Bool) {
        run(.setWindowForm(on))
    }

    /// Customise Home from the menu, in the window.
    func customiseHome() {
        prepare(.page(.home))
        model?.homeSnapshot = (preferences.homeLayout, preferences.enabledWidgets, preferences.homeProfile)
        model?.editingHome = true
        run(.activateShell)
    }

    // MARK: Tearing the shelf off

    /// The open shelf was pulled off: the window opens on what it showed, held by its title bar.
    func tearOff(_ view: ShelfView, at pointer: CGPoint) {
        prepare(view)
        let visible = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }?.visibleFrame
        let size = preferences.shelfWindowFrame.flatMap(ShelfWindowFrame.decode)?.size ?? ShelfWindowFrame.defaultSize
        if let visible {
            let frame = ShelfWindowFrame.tornOff(at: pointer, size: size, in: visible)
            tearAnchor = CGVector(dx: pointer.x - frame.minX, dy: pointer.y - frame.minY)
            preferences.shelfWindowFrame = ShelfWindowFrame.encode(frame)
        }
        run(.openAsWindow)
    }

    /// Follows the pointer until the button is let go.
    func followTearOff(to pointer: CGPoint) {
        guard let window, let anchor = tearAnchor else { return }
        window.setFrameOrigin(CGPoint(x: pointer.x - anchor.dx, y: pointer.y - anchor.dy))
    }

    func endTearOff() {
        guard tearAnchor != nil else { return }
        tearAnchor = nil
        saveFrame()
    }

    // MARK: Effects

    private func run(_ event: ShelfWindowState.Event, applyShell: @MainActor (FormFactor) -> Void = { _ in }) {
        var next = state
        let effects = next.handle(event)
        isOpen = next.isOpen
        if preferences.windowForm != next.windowForm { preferences.windowForm = next.windowForm }
        for effect in effects {
            switch effect {
            case .closeShelves: services.closeShelves()
            case .showWindow: show()
            case .focusWindow: focus()
            case .hideWindow: hide()
            case .openShelf: break  // Callers only come here once the shell has handed over.
            case .applyShellForm(let form): applyShell(form)
            }
        }
    }

    /// Points the window's sidebar at the row the request asked for.
    private func prepare(_ view: ShelfView?, session: String? = nil) {
        guard let model = model ?? makeModel() else { return }
        self.model = model
        if let view { navigation.open(WindowDestination(view, gridWidgets: preferences.gridWidgets)) }
        if let session { model.focusedSession = session }
    }

    private func show() {
        guard let model = model ?? makeModel(), let main = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        else { return }
        self.model = model
        model.speed = preferences.animationSpeed
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shell = services.formUnderPointer()
        model.forms = FormFactor.available(systemIsland: shell.systemIsland)
        model.standInForm = shell.form
        // Back in the view tree, so the pages start their cameras and pollers again.
        model.phase = .open
        let window = window ?? makeWindow(model: model)
        self.window = window
        hiding = false
        let frame = ShelfWindowFrame.fitted(
            preferences.shelfWindowFrame.flatMap(ShelfWindowFrame.decode),
            screens: NSScreen.screens.map(\.visibleFrame), main: main)
        // Torn off, it's already under the pointer and follows it, so only its opacity animates:
        // a moving frame would fight the pointer.
        let tornOff = tearAnchor != nil
        animating = !tornOff
        window.setFrame(frame, display: false)
        if !tornOff { window.setFrameOrigin(nudge(frame, toward: shellRect(frame)).origin) }
        window.alphaValue = 0
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        syncFrameRate()
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if !tornOff { window.animator().setFrameOrigin(frame.origin) }
            window.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { if !tornOff { self?.animating = false } }
        }
    }

    /// ⌘1 to ⌘3 and ⌘0 while the window is key. Wisp has no main menu to carry them.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            let target = event.window
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.owns(target),
                    let action = WindowKeys.action(keyCode: keyCode, commandOnly: modifiers == .command)
                else { return false }
                self.navigation.perform(action)
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Whether `window` is the shelf window, whose own keys (Esc in a field) aren't the shell's.
    func owns(_ window: NSWindow?) -> Bool {
        guard let window, let own = self.window else { return false }
        return window === own
    }

    private func focus() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Fades the window back toward the shell it came from, then orders it out.
    private func hide() {
        guard let window, !hiding else { return }
        guard window.isVisible else {
            // Already off screen (stepped aside for a capture): there's nothing to fade, but the
            // page still has to stop.
            if model?.phase == .open {
                saveFrame()
                finishHiding()
            }
            return
        }
        saveFrame()
        hiding = true
        animating = true
        let frame = window.frame
        let to = nudge(frame, toward: shellRect(frame))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrameOrigin(to.origin)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hiding else { return }
                self.hiding = false
                self.finishHiding()
                window.orderOut(nil)
                window.setFrameOrigin(frame.origin)
                window.alphaValue = 1
                self.animating = false
            }
        }
    }

    private func finishHiding() {
        // Out of the view tree while hidden, so the camera, pollers and scripts stop.
        model?.phase = .closed
        // Customise Home ends with its changes kept, as when the notch's shelf closes.
        if model?.editingHome == true { model?.endHomeEditing() }
        removeKeyMonitor()
    }

    /// A short way from `frame` toward the shell, for the window to leave by or come out
    /// of. Reduce Motion keeps it in place, so only the fade remains.
    private func nudge(_ frame: CGRect, toward shell: CGRect?) -> CGRect {
        guard let shell, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return frame }
        let share: CGFloat = 0.15
        return frame.offsetBy(dx: (shell.midX - frame.midX) * share, dy: (shell.midY - frame.midY) * share)
    }

    private func saveFrame() {
        guard let window, !animating, tearAnchor == nil else { return }
        let encoded = ShelfWindowFrame.encode(window.frame)
        if preferences.shelfWindowFrame != encoded { preferences.shelfWindowFrame = encoded }
    }

    private func makeModel() -> NotchModel? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        // An island's layout gives the pages their plain island margins; the window has no notch.
        let model = NotchModel(
            layout: NotchGeometry.layout(for: screen.metrics, prefersIsland: true, placement: .top),
            services: services)
        model.phase = .open
        model.showsActivities = false
        model.onSetForm = { [weak self] form in self?.services.setForm(form) }
        return model
    }

    private func makeWindow(model: NotchModel) -> ShelfWindow {
        let window = ShelfWindow(
            contentRect: CGRect(origin: .zero, size: ShelfWindowFrame.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "Wisp"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onMinimise = { [weak self] in self?.run(.putAway) }
        let host = NSHostingController(rootView: ShelfWindowView(model: model, navigation: navigation))
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = host
        // As in Settings: the sidebar runs to the top edge under a unified toolbar.
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentMinSize = ShelfWindowFrame.minimumSize
        return window
    }

    // MARK: NSWindowDelegate

    /// Closing puts the window away like minimising, keeping it for next time.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        run(.putAway)
        return false
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }

    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }

    func windowDidChangeScreen(_ notification: Notification) { syncFrameRate() }

    /// Tunes the page springs to the display the window is on, as the notch does for its screen.
    private func syncFrameRate() {
        guard let model, let screen = window?.screen ?? NSScreen.main else { return }
        model.framesPerSecond = screen.maximumFramesPerSecond
    }
}

/// A window whose minimise button goes back to the shell instead of the Dock.
final class ShelfWindow: NSWindow {
    var onMinimise: @MainActor () -> Void = {}

    override func performMiniaturize(_ sender: Any?) { onMinimise() }

    override func miniaturize(_ sender: Any?) { onMinimise() }
}
