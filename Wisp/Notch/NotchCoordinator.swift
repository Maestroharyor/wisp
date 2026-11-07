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
        services.shelfWindow.shellRect = { [weak self] frame in self?.shellRect(near: frame) }
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
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                // The shelf window's Esc is its own: a field's, or back out of a solo widget.
                if self.services.shelfWindow.owns(event.window) { return self.services.shelfWindow.leaveSoloWidget() }
                return self.dismissOpenShelves()
            }
            return handled ? nil : event
        }
        observePreferences()
    }

    /// Toggles the shelf on the display under the pointer.
    func toggleShelf() {
        guard services.shelfWindow.opensUnderShell else {
            services.shelfWindow.toggle()
            return
        }
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

    /// The form shown as current there: Window while that form is on.
    func formUnderPointer() -> (form: FormFactor, systemIsland: Bool) {
        guard let controller = targetController() else { return (services.shelfWindow.form(shell: .notch), false) }
        let shell = FormFactor(placement: controller.layout.placement)
        return (services.shelfWindow.form(shell: shell), controller.systemIsland)
    }

    func setForm(_ form: FormFactor) {
        services.shelfWindow.pick(form) { [weak self] shellForm in
            guard let self, let controller = self.targetController() else { return }
            // Already that form (leaving the window for the shell it had): applying it again
            // would forget a moved island's spot.
            guard shellForm != FormFactor(placement: controller.layout.placement) else { return }
            controller.dismiss()
            self.preferences.setForm(shellForm, for: controller.screenUUID)
        }
    }

    /// The closed shell on the display holding most of `frame`, for the window to leave toward.
    private func shellRect(near frame: CGRect) -> CGRect? {
        let screen = NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
        let controller = screen?.displayUUID.flatMap { controllers[$0] } ?? targetController()
        return controller?.layout.closedRect
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    var hasOpenShelf: Bool { controllers.values.contains { $0.phase == .open } }

    /// Hyper+F: the next form on the display under the pointer.
    func cycleForm() {
        let (form, systemIsland) = formUnderPointer()
        setForm(form.next(systemIsland: systemIsland))
    }

    /// Where dictation goes right now (see `DictationTarget.choose`).
    func dictationTarget() -> DictationTarget {
        let shelves = controllers.values
        return DictationTarget.choose(
            draftSession: shelves.lazy.compactMap(\.dictationDraftSession).first,
            questionCard: shelves.lazy.compactMap(\.dictationQuestion).first)
    }

    /// Hands dictated text to the display that shows its draft box or question card. False
    /// when it has closed (the shelf closed, or the question was answered elsewhere).
    func deliverDictation(_ text: String, to target: DictationTarget) -> Bool {
        let controller: NotchController? =
            switch target {
            case .agentDraft(let session): controllers.values.first { $0.dictationDraftSession == session }
            case .questionAnswer(let id): controllers.values.first { $0.dictationQuestion == id }
            case .focusedApp: nil
            }
        guard let controller else { return false }
        controller.receiveDictation(text, target: target)
        return true
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
            guard let uuid = screen.displayUUID, let layout = preferences.layout(for: screen, uuid: uuid) else {
                continue
            }
            let systemIsland = screen.hasSystemIsland(preferences.islandSetting)
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
            shellDrag = pressedShell(at: location)
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

    /// A press that may become a drag of its shell. Only a shell that owns its press can be
    /// dragged; elsewhere the drag is the app's. Islands move as pills, the top notch tears
    /// off into an orb, and the orb moves.
    private func pressedShell(at location: CGPoint) -> ShellDrag? {
        for (uuid, controller) in controllers {
            let layout = controller.layout
            let kind: ShellDrag.Kind
            if controller.phase == .open {
                // The open shelf tears off into the window, from outside its pages only.
                guard controller.ownsShelfGrab(at: location) else { continue }
                kind = .shelf
            } else if layout.movesAsIsland {
                guard controller.ownsIslandPress(at: location) else { continue }
                kind = .island
            } else if controller.pendingPress, layout.placement.tearsOff {
                kind = layout.placement == .floating ? .orb : .tearOff
            } else {
                continue
            }
            return ShellDrag(
                uuid: uuid, start: location,
                startCentre: CGPoint(x: layout.closedRect.midX, y: layout.closedRect.midY), kind: kind)
        }
        return nil
    }

    /// Moves the orb or an island with the pointer. The notch stretches as it's pulled and
    /// comes off its edge once pulled far enough. While dragging only the panel moves; the
    /// layout is rebuilt on release.
    private func dragShell(to location: CGPoint) {
        guard var drag = shellDrag, let controller = controllers[drag.uuid],
            let screen = NSScreen.screens.first(where: { $0.displayUUID == drag.uuid })
        else { return }
        if drag.kind == .shelf {
            tearOffShelf(&drag, to: location, controller: controller)
            shellDrag = drag
            return
        }
        let free = drag.kind != .tearOff
        let centre =
            free
            ? CGPoint(
                x: drag.startCentre.x + location.x - drag.start.x, y: drag.startCentre.y + location.y - drag.start.y)
            : location
        if let last = drag.centre {
            controller.moveOrb(by: CGVector(dx: centre.x - last.x, dy: centre.y - last.y))
            drag.centre = centre
            shellDrag = drag
            return
        }
        guard OrbGeometry.startsDrag(from: drag.start, to: location, floating: free) else {
            if !free {
                let pulled = hypot(location.x - drag.start.x, location.y - drag.start.y)
                controller.setPull(pulled / OrbGeometry.tearOffDistance)
            }
            return
        }
        controller.cancelPress()
        controller.setPull(0)
        let systemIsland = screen.hasSystemIsland(preferences.islandSetting)
        switch drag.kind {
        case .island:
            // Still the same pill, now free of its spot.
            controller.update(
                layout: NotchGeometry.layout(
                    for: screen.metrics, prefersIsland: true, placement: controller.layout.placement,
                    islandCentre: centre, avoidsTopCentre: systemIsland))
        case .shelf:
            return
        case .orb, .tearOff:
            controller.update(
                layout: NotchGeometry.layout(
                    for: screen.metrics, prefersIsland: true, placement: .floating, orbCentre: centre,
                    avoidsTopCentre: systemIsland))
        }
        if drag.kind == .tearOff { controller.popIn() }
        // Where the orb really is: the layout may have nudged it onto the screen.
        let placed = controller.layout.closedRect
        drag.centre = centre
        drag.offset = CGVector(dx: placed.midX - centre.x, dy: placed.midY - centre.y)
        shellDrag = drag
    }

    /// Pulled far enough, the open shelf folds away and the window takes its page, held by
    /// its title bar under the pointer until the button is let go.
    private func tearOffShelf(_ drag: inout ShellDrag, to location: CGPoint, controller: NotchController) {
        if drag.centre != nil {
            services.shelfWindow.followTearOff(to: location)
            return
        }
        guard ShelfTearOff.tearsOff(from: drag.start, to: location) else { return }
        let shown = controller.shown
        services.shelfWindow.tearOff(shown.view, fromPill: shown.fromPill, returnPage: shown.returnPage, at: location)
        drag.centre = location
    }

    /// Settles a dragged orb: it glides flush against a nearby edge, or shrinks away and docks
    /// back on its edge when dropped at the top centre.
    private func dropShell(_ drag: ShellDrag) {
        if drag.kind == .shelf {
            services.shelfWindow.endTearOff()
            return
        }
        guard let controller = controllers[drag.uuid], let dragged = drag.centre,
            let screen = NSScreen.screens.first(where: { $0.displayUUID == drag.uuid })
        else { return }
        let visible = screen.visibleFrame
        let systemIsland = screen.hasSystemIsland(preferences.islandSetting)
        let seen = CGPoint(x: dragged.x + drag.offset.dx, y: dragged.y + drag.offset.dy)
        if drag.kind == .island {
            dropIsland(drag, at: seen, controller: controller, screen: screen)
            return
        }
        let size = controller.layout.closedRect.width
        let wasFloating = drag.kind == .orb && preferences.placement(for: drag.uuid) == .floating
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

    /// Settles a dragged island: it stays where it's dropped, flush with a nearby edge, or goes
    /// home when dropped back on its own spot. Either way it glides there from the drop.
    private func dropIsland(_ drag: ShellDrag, at seen: CGPoint, controller: NotchController, screen: NSScreen) {
        let systemIsland = screen.hasSystemIsland(preferences.islandSetting)
        let placement = controller.layout.placement
        let home = NotchGeometry.layout(
            for: screen.metrics, prefersIsland: true, placement: placement, avoidsTopCentre: systemIsland
        ).closedRect
        let before = preferences.islandSpots
        controller.settle(from: seen)
        switch IslandDrop.outcome(
            dropped: seen, in: screen.visibleFrame, size: controller.layout.closedRect.size,
            systemIsland: systemIsland, home: CGPoint(x: home.midX, y: home.midY))
        {
        case .restore: preferences.moveIslandBack(drag.uuid)
        case .move(let point): preferences.moveIsland(drag.uuid, to: IslandSpot(placement: placement, centre: point))
        }
        // A changed setting rebuilds through observation; otherwise put the dragged layout back.
        if before == preferences.islandSpots { rebuild() }
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
            _ = preferences.islandSpots
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

extension Preferences {
    /// The display's layout from the current settings, or nil when Wisp is hidden there.
    /// Settings reads it too, to tell whether an island is really showing moved.
    @MainActor
    func layout(for screen: NSScreen, uuid: String) -> NotchLayout? {
        let metrics = screen.metrics
        let systemIsland = screen.hasSystemIsland(islandSetting)
        let style = DisplayStyle.resolve(
            displayStyle(for: uuid), hasNotch: metrics.hasCameraHousing,
            showOnExternal: showOnExternalDisplays,
            externalIsland: externalStyle == .island,
            systemIsland: systemIsland
        )
        if style == .hidden { return nil }
        let placement = placement(for: uuid).clear(ofSystemIsland: systemIsland)
        // Stored centres are refitted to the display's current frame, so a resolution or
        // arrangement change can't strand a shell off screen.
        return NotchGeometry.layout(
            for: metrics, prefersIsland: style == .island, placement: placement, orbCentre: orbCentre(for: uuid),
            islandCentre: islandSpot(for: uuid)?.centre(for: placement), avoidsTopCentre: systemIsland)
    }
}

/// A press on a closed shell that may become a drag of it.
private struct ShellDrag {
    let uuid: String
    let start: CGPoint
    let startCentre: CGPoint
    let kind: Kind
    /// Where the pointer has put the orb or island, once it's moving.
    var centre: CGPoint?
    /// How far the first layout nudged the shell from the pointer to keep it on screen.
    var offset = CGVector(dx: 0, dy: 0)

    enum Kind {
        /// The top notch, which needs a deliberate pull to tear off into an orb.
        case tearOff
        /// Already an orb, so it moves at a nudge.
        case orb
        /// An island pill, which moves at a nudge and stays a pill.
        case island
        /// The open shelf, which a deliberate pull tears off into the window.
        case shelf
    }
}
