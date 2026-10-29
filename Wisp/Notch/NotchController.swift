import AppKit
import SwiftUI
import WispCore

/// Owns the panel and open/close behaviour for one display.
@MainActor
final class NotchController {
    let screenUUID: String

    private let panel: NotchPanel
    private let model: NotchModel
    private let services: AppServices
    private var machine = NotchMachine()
    private var pointerInside = false
    private var dwellTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var dragEndTask: Task<Void, Never>?

    /// Grace period before a shelf closes after the pointer leaves.
    private let closeDelay: Duration = .milliseconds(300)

    init(screenUUID: String, layout: NotchLayout, services: AppServices) {
        self.screenUUID = screenUUID
        self.services = services
        model = NotchModel(layout: layout, services: services)
        panel = NotchPanel(frame: layout.panelFrame)

        let hosting = NSHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
        syncSettings()
        model.onReplyEnded = { [weak self] in self?.endReply() }
        observeActivity()
    }

    /// An approval card has buttons, so the closed panel stops being click-through while it shows.
    private var showsApproval: Bool {
        if case .agentApproval = model.activity { return true }
        return false
    }

    private func observeActivity() {
        withObservationTracking {
            _ = model.activity
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateClickThrough()
                self?.observeActivity()
            }
        }
    }

    private func updateClickThrough() {
        panel.ignoresMouseEvents = machine.phase == .closed && !model.dragging && !isReplying && !showsApproval
    }

    var isReplying: Bool { model.replyingTo != nil }

    var phase: NotchPhase { machine.phase }
    var layout: NotchLayout { model.layout }

    var showsActivities: Bool {
        get { model.showsActivities }
        set { model.showsActivities = newValue }
    }

    func update(layout: NotchLayout) {
        guard layout != model.layout else { return }
        model.layout = layout
        panel.setFrame(layout.panelFrame, display: true)
    }

    func pointerMoved(to location: CGPoint) {
        let inside = model.contains(location)
        guard inside != pointerInside else { return }
        pointerInside = inside
        send(inside ? .pointerEntered : .pointerExited)
    }

    func leftMouseDown(at location: CGPoint) {
        if handleNotificationClick(at: location) { return }
        // The approval card's own buttons take the click.
        if machine.phase != .open, showsApproval, model.contains(location) { return }
        if model.contains(location) {
            if machine.phase == .open {
                // Let text fields (notes, search) take keyboard input without activating Wisp.
                panel.makeKey()
            } else {
                send(.clicked)
            }
        } else if machine.phase == .open {
            send(.clickedOutside)
        }
    }

    func rightMouseDown(at location: CGPoint) {
        guard model.contains(location) else { return }
        NotchMenu.show(
            at: location,
            customiseHome: { [weak self] in self?.customiseHome() },
            services: services
        )
    }

    /// A file drag moved; open the drop tiles when it reaches the notch.
    func fileDragMoved(to location: CGPoint) {
        let target = layout.hitRegion(for: model.surfaceRect).insetBy(dx: -24, dy: -24)
        let over = target.contains(location)
        if over, !model.dragging {
            dragEndTask?.cancel()
            model.dragging = true
            panel.ignoresMouseEvents = false
            send(.dragEntered)
        } else if !over, model.dragging, machine.phase == .open,
            !model.surfaceRect.insetBy(dx: -24, dy: -24).contains(location)
        {
            model.dragging = false
            pointerMoved(to: location)
        }
    }

    func fileDragEnded() {
        guard model.dragging else { return }
        dragEndTask?.cancel()
        // Give the drop handler time to run before the tiles disappear.
        dragEndTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.model.dragging = false
            self.pointerInside = self.model.contains(NSEvent.mouseLocation)
            if !self.pointerInside { self.send(.pointerExited) }
        }
    }

    func toggle() { send(.hotkey) }

    func dismiss() {
        if isReplying {
            services.endReply(sentText: nil)
            endReply()
            return
        }
        send(.escape)
    }

    /// Clicking a notification card starts a reply (or opens the app when Wisp
    /// cannot answer it); clicking elsewhere while replying cancels.
    private func handleNotificationClick(at location: CGPoint) -> Bool {
        if isReplying {
            if model.contains(location) {
                panel.makeKey()
            } else {
                dismiss()
            }
            return true
        }
        guard machine.phase != .open, case .notification(let item) = model.activity, model.contains(location) else {
            return false
        }
        if services.notifications.canReply(to: item) {
            services.beginReply(to: item)
            model.replyingTo = item
            panel.ignoresMouseEvents = false
            panel.makeKey()
        } else {
            services.notifications.openApp(for: item)
            services.activities.remove(.notification)
        }
        return true
    }

    private func endReply() {
        model.replyingTo = nil
        panel.resignKey()
        updateClickThrough()
    }

    /// Esc on a solo widget goes back to the grid rather than closing the shelf.
    func leaveSoloWidget() -> Bool {
        guard machine.phase == .open, model.soloWidget != nil else { return false }
        model.soloWidget = nil
        return true
    }

    /// A profile switch picks the page the shelf opens on; an open shelf stays put.
    func setRestingPage(_ page: ShelfPage) {
        guard machine.phase != .open else { return }
        model.page = page
    }

    func open(page: ShelfPage) {
        model.page = page
        if machine.phase != .open { send(.hotkey) }
    }

    func tearDown() {
        dwellTask?.cancel()
        closeTask?.cancel()
        dragEndTask?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    private func customiseHome() {
        model.page = .home
        model.homeSnapshot = (services.preferences.homeLayout, services.preferences.enabledWidgets)
        model.editingHome = true
        if machine.phase != .open { send(.hotkey) }
    }

    private func syncSettings() {
        let preferences = services.preferences
        machine.opensOnHover = preferences.openTrigger == .hover
        model.speed = preferences.animationSpeed
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let screen = NSScreen.screens.first(where: { $0.displayUUID == screenUUID }) {
            model.framesPerSecond = screen.maximumFramesPerSecond
        }
    }

    private func send(_ event: NotchEvent) {
        syncSettings()
        let wasOpen = machine.phase == .open
        for effect in machine.handle(event) {
            apply(effect)
        }
        render(wasOpen: wasOpen)
    }

    private func apply(_ effect: NotchEffect) {
        switch effect {
        case .scheduleDwell:
            dwellTask?.cancel()
            let delay = Duration.milliseconds(Int(services.preferences.hoverDelay * 1000))
            dwellTask = schedule(after: delay, .dwellElapsed)
        case .cancelDwell:
            dwellTask?.cancel()
            dwellTask = nil
        case .scheduleClose:
            closeTask?.cancel()
            closeTask = schedule(after: closeDelay, .closeDelayElapsed)
        case .cancelClose:
            closeTask?.cancel()
            closeTask = nil
        }
    }

    private func schedule(after delay: Duration, _ event: NotchEvent) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.send(event)
        }
    }

    private func render(wasOpen: Bool) {
        model.phase = machine.phase
        // Click-through while closed, so the menu bar under the panel keeps working.
        updateClickThrough()

        if machine.phase == .open, machine.pinned {
            // Keyboard-opened: take key status (without activating the app) so Esc reaches us.
            panel.makeKey()
        }
        if wasOpen, machine.phase == .closed {
            panel.resignKey()
            model.editingHome = false
            model.soloWidget = nil
            model.dragging = false
            // Re-sync with the smaller closed region so the next hover is detected cleanly.
            pointerInside = model.contains(NSEvent.mouseLocation)
        }
    }
}
