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
    private var shellDrag: ShellDrag?
    private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "notch")

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

    func openWidget(_ kind: WidgetKind) {
        targetController()?.open(widget: kind)
    }

    func formUnderPointer() -> (form: FormFactor, systemIsland: Bool) {
        guard let controller = targetController() else { return (.notch, false) }
        return (FormFactor(placement: controller.layout.placement), controller.systemIsland)
    }

    func setForm(_ form: FormFactor) {
        guard let controller = targetController() else { return }
        controller.dismiss()
        preferences.setForm(form, for: controller.screenUUID)
    }

    var hasOpenShelf: Bool { controllers.values.contains { $0.phase == .open } }

    /// Hyper+F: the next form on the display under the pointer.
    func cycleForm() {
        let (form, systemIsland) = formUnderPointer()
        setForm(form.next(systemIsland: systemIsland))
    }

    private func targetController() -> NotchController? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
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
            let systemIsland = screen.hasSystemIsland(preferences.islandSetting)
            let style = DisplayStyle.resolve(
                preferences.displayStyle(for: uuid), hasNotch: metrics.hasCameraHousing,
                showOnExternal: preferences.showOnExternalDisplays,
                externalIsland: preferences.externalStyle == .island,
                systemIsland: systemIsland
            )
            if style == .hidden { continue }
            let layout = NotchGeometry.layout(
                for: metrics, prefersIsland: style == .island,
                placement: preferences.placement(for: uuid).clear(ofSystemIsland: systemIsland),
                orbCentre: preferences.orbCentre(for: uuid), avoidsTopCentre: systemIsland)
            current.insert(uuid)
            log.notice(
                "display \(uuid, privacy: .public) style=\(String(describing: layout.style), privacy: .public) closed=\(String(describing: layout.closedRect), privacy: .public) panel=\(String(describing: layout.panelFrame), privacy: .public)"
            )
            let controller =
                controllers[uuid] ?? NotchController(screenUUID: uuid, layout: layout, services: services)
            controller.systemIsland = systemIsland
            let newForm = controllers[uuid].map { $0.layout.placement != layout.placement } ?? false
            controller.update(layout: layout)
            // A new form springs in rather than appearing in place.
            if newForm { controller.popIn() }
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

    /// NSMouseInRect counts the top edge, where the pointer sits when pushed against it.
    private func displayUUID(at point: CGPoint) -> String? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }?.displayUUID
    }

    /// Activities follow the pointer between displays when that option is on.
    private func pointerMovedAcrossDisplays(_ location: CGPoint) {
        guard preferences.activityDisplay == .pointer else { return }
        // A reply's card and field live on one display; moving them would strand the reply.
        guard !controllers.values.contains(where: \.isReplying) else { return }
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
            // Only a shell that owns its press can be dragged; elsewhere the drag is the app's.
            shellDrag = controllers.first { $0.value.pendingPress && $0.value.layout.placement.tearsOff }.map {
                uuid, controller in
                ShellDrag(
                    uuid: uuid, start: location,
                    startCentre: CGPoint(x: controller.layout.closedRect.midX, y: controller.layout.closedRect.midY),
                    floating: controller.layout.placement == .floating)
            }
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
            } else if shellDrag != nil {
                dragShell(to: location)
            } else {
                controllers.values.forEach { $0.pointerMoved(to: location) }
            }
        case .leftUp:
            if let drag = shellDrag, drag.centre != nil {
                dropShell(drag)
            } else {
                if let drag = shellDrag { controllers[drag.uuid]?.releasePull() }
                controllers.values.forEach { $0.leftMouseUp(at: location) }
            }
            shellDrag = nil
            if fileDragActive {
                controllers.values.forEach { $0.fileDragEnded() }
                services.pocket.dragEnded()
                services.ring.dragEnded()
            }
            fileDragActive = false
        }
    }

    /// Moves the orb with the pointer. The notch stretches as it's pulled and comes off its
    /// edge once pulled far enough. While dragging only the panel moves; the layout is rebuilt
    /// on release.
    private func dragShell(to location: CGPoint) {
        guard var drag = shellDrag, let controller = controllers[drag.uuid],
            let screen = NSScreen.screens.first(where: { $0.displayUUID == drag.uuid })
        else { return }
        let centre =
            drag.floating
            ? CGPoint(
                x: drag.startCentre.x + location.x - drag.start.x, y: drag.startCentre.y + location.y - drag.start.y)
            : location
        if let last = drag.centre {
            controller.moveOrb(by: CGVector(dx: centre.x - last.x, dy: centre.y - last.y))
            drag.centre = centre
            shellDrag = drag
            return
        }
        guard OrbGeometry.startsDrag(from: drag.start, to: location, floating: drag.floating) else {
            if !drag.floating {
                let pulled = hypot(location.x - drag.start.x, location.y - drag.start.y)
                controller.setPull(pulled / OrbGeometry.tearOffDistance)
            }
            return
        }
        controller.cancelPress()
        controller.setPull(0)
        controller.update(
            layout: NotchGeometry.layout(
                for: screen.metrics, prefersIsland: true, placement: .floating, orbCentre: centre,
                avoidsTopCentre: screen.hasSystemIsland(preferences.islandSetting)))
        if !drag.floating { controller.popIn() }
        // Where the orb really is: the layout may have nudged it onto the screen.
        let placed = controller.layout.closedRect
        drag.centre = centre
        drag.offset = CGVector(dx: placed.midX - centre.x, dy: placed.midY - centre.y)
        shellDrag = drag
    }

    /// Settles a dragged orb: it glides flush against a nearby edge, or shrinks away and docks
    /// back on its edge when dropped at the top centre.
    private func dropShell(_ drag: ShellDrag) {
        guard let controller = controllers[drag.uuid], let dragged = drag.centre,
            let screen = NSScreen.screens.first(where: { $0.displayUUID == drag.uuid })
        else { return }
        let visible = screen.visibleFrame
        let systemIsland = screen.hasSystemIsland(preferences.islandSetting)
        let seen = CGPoint(x: dragged.x + drag.offset.dx, y: dragged.y + drag.offset.dy)
        let size = controller.layout.closedRect.width
        let wasFloating = drag.floating && preferences.placement(for: drag.uuid) == .floating
        let target: CGPoint
        switch OrbDrop.outcome(
            dropped: seen, in: visible, size: size, systemIsland: systemIsland, wasFloating: wasFloating)
        {
        case .dock:
            controller.vanish { [weak self] in self?.preferences.dockOrb(drag.uuid) }
            return
        case .restore:
            // Nothing was saved during the drag, so rebuilding puts the notch back.
            rebuild()
            return
        case .float(let point):
            target = point
        }
        let before = (preferences.displayPlacements, preferences.orbCentres)
        controller.settle(from: seen)
        preferences.floatOrb(drag.uuid, at: target)
        // A changed setting rebuilds through observation; otherwise put the dragged layout back.
        if before == (preferences.displayPlacements, preferences.orbCentres) { rebuild() }
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
        if !open.isEmpty { return true }
        // Nothing open: Esc puts away a card or alert instead. Every display shows the same one.
        return controllers.values.contains { $0.dismissActivity() }
    }

    private func observePreferences() {
        withObservationTracking {
            _ = preferences.orbCentres
            _ = preferences.showOnExternalDisplays
            _ = preferences.externalStyle
            _ = preferences.displayStyles
            _ = preferences.placement
            _ = preferences.displayPlacements
            _ = preferences.islandSetting
            _ = preferences.activityDisplay
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuild()
                self?.observePreferences()
            }
        }
    }
}

/// A press on a closed shell that may become a drag of it.
private struct ShellDrag {
    let uuid: String
    let start: CGPoint
    let startCentre: CGPoint
    /// Already an orb, so it moves at a nudge rather than tearing off.
    let floating: Bool
    /// Where the pointer has put the orb, once it's moving.
    var centre: CGPoint?
    /// How far the first layout nudged the orb from the pointer to keep it on screen.
    var offset = CGVector(dx: 0, dy: 0)
}
