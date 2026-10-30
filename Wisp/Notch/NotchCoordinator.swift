import AppKit
import OSLog
import Observation
import WispCore

/// Keeps one `NotchController` per display, rebuilt when displays change, and
/// routes pointer, drag, keyboard and hotkey input to them.
@MainActor
final class NotchCoordinator {
    private let services: AppServices
    private let pointer = PointerMonitor()
    private var controllers: [String: NotchController] = [:]
    private var screenObserver: NSObjectProtocol?
    private var escapeMonitor: Any?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var fileDragActive = false
    private var pointerDisplay: String?
    private var shake = ShakeDetector()
    private var dragStarted = Date.now
    private let log = Logger(subsystem: "com.maestro.wisp", category: "notch")

    private var preferences: Preferences { services.preferences }

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        services.restingPage = { [weak self] page in
            self?.controllers.values.forEach { $0.setRestingPage(page) }
        }
        services.closeShelves = { [weak self] in
            self?.controllers.values.filter { $0.phase == .open }.forEach { $0.dismiss() }
        }
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        pointer.start { [weak self] action, location in
            self?.route(action, at: location)
        }
        pointer.startScroll { [weak self] scroll, location in
            guard let self, self.preferences.swipeGestures else { return }
            self.controllers.values.forEach { $0.scrolled(scroll, at: location) }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == KeyCodes.escape else { return event }
            let handled = MainActor.assumeIsolated { self?.dismissOpenShelves() ?? false }
            return handled ? nil : event
        }
        observePreferences()
    }

    /// Toggles the shelf on the display under the pointer.
    func toggleShelf() {
        let target = targetController()
        for controller in controllers.values where controller !== target && controller.phase == .open {
            controller.dismiss()
        }
        target?.toggle()
    }

    func openShelf(page: ShelfPage) {
        targetController()?.open(page: page)
    }

    private func targetController() -> NotchController? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return screen?.displayUUID.flatMap { controllers[$0] }
            ?? controllers.values.first { $0.layout.style == .notch }
            ?? controllers.values.first
    }

    private func rebuild() {
        var current = Set<String>()
        let screens = NSScreen.screens

        for screen in screens {
            guard let uuid = screen.displayUUID else { continue }
            let metrics = screen.metrics
            let style = DisplayStyle.resolve(
                preferences.displayStyle(for: uuid), hasNotch: metrics.hasCameraHousing,
                showOnExternal: preferences.showOnExternalDisplays, externalIsland: preferences.externalStyle == .island
            )
            if style == .hidden { continue }
            let layout = NotchGeometry.layout(for: metrics, prefersIsland: style == .island)
            current.insert(uuid)
            log.notice(
                "display \(uuid, privacy: .public) style=\(String(describing: layout.style), privacy: .public) closed=\(String(describing: layout.closedRect), privacy: .public) panel=\(String(describing: layout.panelFrame), privacy: .public)"
            )
            let controller =
                controllers[uuid] ?? NotchController(screenUUID: uuid, layout: layout, services: services)
            controller.update(layout: layout)
            controllers[uuid] = controller
        }
        for (uuid, controller) in controllers where !current.contains(uuid) {
            controller.tearDown()
            controllers[uuid] = nil
        }
        pointerDisplay = displayUUID(at: NSEvent.mouseLocation)
        assignActivityDisplays()
    }

    /// Shows live activities on the display(s) chosen in Settings.
    private func assignActivityDisplays() {
        let screens = NSScreen.screens
        let chosen = preferences.activityDisplay.displays(
            among: screens.compactMap(\.displayUUID).filter { controllers[$0] != nil },
            builtIn: screens.first(where: \.isBuiltIn)?.displayUUID,
            pointer: pointerDisplay,
            main: NSScreen.main?.displayUUID
        )
        for (uuid, controller) in controllers {
            let shows = chosen.contains(uuid)
            if controller.showsActivities != shows { controller.showsActivities = shows }
        }
    }

    private func displayUUID(at point: CGPoint) -> String? {
        NSScreen.screens.first { $0.frame.contains(point) }?.displayUUID
    }

    /// Activities follow the pointer between displays when that option is on.
    private func pointerMovedAcrossDisplays(_ location: CGPoint) {
        guard preferences.activityDisplay == .pointer else { return }
        let display = displayUUID(at: location)
        guard let display, display != pointerDisplay else { return }
        pointerDisplay = display
        assignActivityDisplays()
    }

    private func route(_ action: PointerMonitor.Action, at location: CGPoint) {
        switch action {
        case .moved:
            pointerMovedAcrossDisplays(location)
            controllers.values.forEach { $0.pointerMoved(to: location) }
        case .leftDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            fileDragActive = false
            shake.reset()
            dragStarted = .now
            controllers.values.forEach { $0.leftMouseDown(at: location) }
        case .rightDown:
            controllers.values.forEach { $0.rightMouseDown(at: location) }
        case .dragged:
            if !fileDragActive {
                fileDragActive = isFileDrag()
                if fileDragActive, preferences.pocketTrigger == .dragStart { services.pocket.show(at: location) }
            }
            if fileDragActive {
                if preferences.pocketTrigger == .shake,
                    shake.add(location, at: Date.now.timeIntervalSince(dragStarted))
                {
                    services.pocket.show(at: location)
                }
                controllers.values.forEach { $0.fileDragMoved(to: location) }
            } else {
                controllers.values.forEach { $0.pointerMoved(to: location) }
            }
        case .leftUp:
            if fileDragActive {
                controllers.values.forEach { $0.fileDragEnded() }
                services.pocket.dragEnded()
            }
            fileDragActive = false
        }
    }

    /// A drag that put file URLs on the drag pasteboard since the mouse went down.
    private func isFileDrag() -> Bool {
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != dragChangeCount else { return false }
        return board.types?.contains(.fileURL) ?? false
    }

    private func dismissOpenShelves() -> Bool {
        let backedOut = controllers.values.filter { $0.leaveSoloWidget() }
        if !backedOut.isEmpty { return true }
        let open = controllers.values.filter { $0.phase == .open || $0.isReplying }
        open.forEach { $0.dismiss() }
        return !open.isEmpty
    }

    private func observePreferences() {
        withObservationTracking {
            _ = preferences.showOnExternalDisplays
            _ = preferences.externalStyle
            _ = preferences.displayStyles
            _ = preferences.activityDisplay
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuild()
                self?.observePreferences()
            }
        }
    }
}
