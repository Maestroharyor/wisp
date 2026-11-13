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
    private var pointerOverBubble = false
    /// On a draggable island's visible shape, where its panel takes the press so a drag can't
    /// also reach the window underneath.
    private var pointerOverIsland = false
    private var dwellTask: Task<Void, Never>?
    private var collapseControlsTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var dragEndTask: Task<Void, Never>?
    private var motionObserver: NSObjectProtocol?
    private var swipe = SwipeDetector()
    /// The card whose countdown is paused because the pointer is on it.
    private var heldSlot: ActivitySlot?
    /// A press on the closed shell. It acts on mouse-up, so dragging the shell moves it instead.
    private(set) var pendingPress = false
    /// Apple's island sits at the top of this display; the notch form isn't offered.
    var systemIsland = false {
        didSet { model.forms = FormFactor.available(systemIsland: systemIsland) }
    }

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
        model.onWantsKey = { [weak self] in self?.panel.makeKey() }
        model.onSetForm = { [weak self] form in
            guard let self else { return }
            self.services.shelfWindow.pick(form) { [weak self] shellForm in
                // Already that form: applying it again would forget a moved island's spot.
                guard let self, shellForm != FormFactor(placement: self.layout.placement) else { return }
                // Fold the shelf away first; the new form comes in once the setting rebuilds.
                self.dismiss()
                self.services.preferences.setForm(shellForm, for: self.screenUUID)
            }
        }
        model.onKeyDone = { [weak self] in
            // An open shelf keeps its key status for its own fields.
            guard let self, self.machine.phase != .open else { return }
            self.panel.resignKey()
        }
        observeActivity()
        // Turning Reduce Motion on takes effect right away, not at the next hover.
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncSettings() }
        }
    }

    /// Approval, Join, call control, finished download, AI result and quick add cards have
    /// buttons, so the closed panel stops being click-through while one shows.
    private var showsApproval: Bool {
        switch model.activity {
        case .agentApproval, .meetingSoon, .downloadDone, .aiResult, .quickIntent: true
        case .meeting: model.showsMeetingControls
        default: false
        }
    }

    private func observeActivity() {
        withObservationTracking {
            _ = model.activity
            _ = services.microphone.inUse
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.closeMeetingControlsAfterCall()
                self?.releaseKeyAfterCard()
                self?.updateCardHover()
                self?.resyncPointer()
                self?.observeActivity()
            }
        }
    }

    /// Setting ignoresMouseEvents to false makes the whole transparent panel catch clicks
    /// (AppKit passes clicks through transparent areas only while the property is untouched),
    /// so a closed panel takes the mouse only while the pointer is over something it handles.
    private func updateClickThrough() {
        // The orb floats over windows; a press on it must not reach the window underneath.
        let overControls =
            pointerInside && (isReplying || showsApproval || showsPillButton || showsCard || isOrb)
        panel.ignoresMouseEvents =
            machine.phase == .closed && !model.dragging && !overControls && !pointerOverBubble && !pointerOverIsland
    }

    /// Notification and two-line cards take their own clicks (close, reply), so they don't
    /// reach the menu bar underneath.
    private var showsCard: Bool {
        switch model.spec {
        case .notification, .medium: true
        default: false
        }
    }

    /// Pauses the countdown of a card the pointer is on, and shows its close button. Small
    /// alert pills keep their clock, so a pointer parked on the notch can't pin them. Leaving,
    /// replying, opening the shelf or the card changing hands the countdown back.
    private func updateCardHover() {
        let slot = services.activities.currentSlot
        let hovering =
            pointerInside && !isReplying && machine.phase != .open && showsCard && slot?.isDismissable == true
        let target = hovering ? slot : nil
        if model.cardHovered != hovering { model.cardHovered = hovering }
        guard target != heldSlot else { return }
        if let heldSlot { services.activities.release(heldSlot) }
        heldSlot = target
        if let target { services.activities.hold(target) }
    }

    /// The controls card belongs to one call: it stays open while another alert passes over
    /// the pill, and goes when the microphone does, so the next call starts as a plain pill.
    private func closeMeetingControlsAfterCall() {
        guard model.meetingControlsOpen, !services.microphone.inUse else { return }
        collapseControlsTask?.cancel()
        model.meetingControlsOpen = false
    }

    /// Folds the controls card back into the pill a few seconds after the pointer leaves it,
    /// and keeps it while the pointer is back on it.
    private func scheduleControlsCollapse(pointerInside inside: Bool) {
        collapseControlsTask?.cancel()
        collapseControlsTask = nil
        guard !inside, model.meetingControlsOpen else { return }
        collapseControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, !self.pointerInside else { return }
            self.model.meetingControlsOpen = false
        }
    }

    /// A card that took the keyboard for typing (an answer, a reason) went away: hand the
    /// keyboard back to the app the user was in.
    private func releaseKeyAfterCard() {
        guard !showsApproval else { return }
        releaseKey()
    }

    /// Gives up the keyboard while closed, even under a card with buttons, so keys Wisp sends
    /// (a paste from the AI card) reach the app in front instead of the notch.
    func releaseKey() {
        guard machine.phase != .open, !isReplying, panel.isKeyWindow else { return }
        panel.resignKey()
    }

    /// Closes the card or alert on show, when it can be closed.
    @discardableResult
    func dismissActivity() -> Bool {
        guard machine.phase != .open, !isReplying, model.activity != nil else { return false }
        heldSlot = nil
        return services.activities.dismissCurrent()
    }

    private var isOrb: Bool { model.isOrb }

    /// Pills with a button at their trailing end: the meeting pill's mute, the watch pill's stop.
    private var showsPillButton: Bool {
        switch model.activity {
        case .meeting: true
        case .regionWatch: watchStopZone != nil
        default: false
        }
    }

    /// Where the watch pill draws its stop button, when it draws one. Only the main pill has
    /// it: as a bubble during a call the watch is just a glyph, and the mute zone stays the call's.
    private var watchStopZone: CGRect? {
        guard case .regionWatch = model.activity else { return nil }
        return SurfaceSizing.pillButtonZone(
            in: model.surfaceRect, placement: layout.anchor, minimal: services.preferences.appearance.minimalPill)
    }

    var isReplying: Bool { model.replyingTo != nil }

    /// The draft box dictation would type into: the open Agents view's selected session.
    var dictationDraftSession: String? { machine.phase == .open ? model.draftSession : nil }

    /// The question card showing under the closed notch, for a dictated answer.
    var dictationQuestion: UUID? {
        guard machine.phase != .open, case .agentApproval(let approval) = model.activity,
            approval.prompt == .question
        else { return nil }
        return approval.id
    }

    /// Puts dictated text into the draft box or the question card on this display.
    func receiveDictation(_ text: String, target: DictationTarget) {
        switch target {
        case .agentDraft(let session):
            model.agentDrafts[session] = DictationText.appending(text, to: model.agentDrafts[session] ?? "")
        case .questionAnswer(let approval):
            model.dictatedAnswer = DictatedAnswer(approval: approval, text: text)
        case .quickInput, .focusedApp:
            break
        }
    }

    var phase: NotchPhase { machine.phase }
    var layout: NotchLayout { model.layout }

    var showsActivities: Bool {
        get { model.showsActivities }
        set { model.showsActivities = newValue }
    }

    /// Where a dropped orb was on screen, so its new layout glides in from there.
    private var settleFrom: CGPoint?
    /// A drag moved the panel without a new layout, so the panel is off its layout's frame.
    private var panelMoved = false

    func update(layout: NotchLayout) {
        let from = settleFrom
        settleFrom = nil
        guard layout != model.layout || panelMoved else { return }
        panelMoved = false
        // The shell may have moved out from under a still pointer (a drop, Move back).
        defer { resyncPointer() }
        model.layout = layout
        // The shell has its new form now, so a docking orb can stop shrinking.
        model.vanishing = false
        guard let from, !model.reduceMotion else {
            panel.setFrame(layout.panelFrame, display: true)
            return
        }
        // Panel-relative positions stay put, so moving the whole panel moves the orb.
        let to = CGPoint(x: layout.closedRect.midX, y: layout.closedRect.midY)
        panel.setFrame(layout.panelFrame.offsetBy(dx: from.x - to.x, dy: from.y - to.y), display: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(layout.panelFrame, display: true)
        }
    }

    /// Moves a dragged orb or island by moving its panel; the layout is rebuilt once it's dropped.
    func moveOrb(by delta: CGVector) {
        panelMoved = true
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + delta.dx, y: panel.frame.minY + delta.dy))
    }

    /// The next layout glides from `point` instead of jumping.
    func settle(from point: CGPoint) {
        settleFrom = point
    }

    /// The notch stretching toward the pointer while it's pulled.
    func setPull(_ amount: CGFloat) {
        model.pull = min(max(amount, 0), 1)
    }

    func releasePull() {
        guard model.pull > 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { model.pull = 0 }
    }

    /// Springs the shell up from smaller after it changed form.
    func popIn() {
        guard !model.reduceMotion else { return }
        model.pops += 1
    }

    /// Shrinks the orb away, then runs `done` (the dock).
    func vanish(then done: @escaping @MainActor () -> Void) {
        guard !model.reduceMotion else {
            done()
            return
        }
        withAnimation(.easeIn(duration: 0.18)) { model.vanishing = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(190))
            done()
            // The dock's rebuild resets this with the new layout; this catches a dock that
            // changed nothing, after that rebuild has had its turn.
            Task { @MainActor [weak self] in self?.model.vanishing = false }
        }
    }

    func pointerMoved(to location: CGPoint) {
        // Bubbles sit outside the hit regions (hovering one doesn't open the shelf), but a
        // click on one must not also reach the menu bar item underneath.
        let overBubble = machine.phase != .open && model.bubble(at: location) != nil
        let overIsland =
            machine.phase != .open && IslandDrag.ownsPointer(at: location, layout: layout, shape: model.surfaceRect)
        if overBubble != pointerOverBubble || overIsland != pointerOverIsland {
            pointerOverBubble = overBubble
            pointerOverIsland = overIsland
            updateClickThrough()
        }
        let inside = model.contains(location)
        guard inside != pointerInside else { return }
        pointerInside = inside
        scheduleControlsCollapse(pointerInside: inside)
        send(inside ? .pointerEntered : .pointerExited)
    }

    func leftMouseDown(at location: CGPoint) {
        if model.showsCloseButton,
            SurfaceSizing.cardCloseZone(in: model.surfaceRect, topInset: model.cardTopInset).contains(location)
        {
            dismissActivity()
            return
        }
        if handleNotificationClick(at: location) { return }
        // The approval card's own buttons take the click.
        if machine.phase != .open, showsApproval, model.contains(location) { return }
        // A bubble swaps into the main pill.
        if machine.phase != .open, let bubble = model.bubble(at: location) {
            services.activities.pin(bubble.slot)
            return
        }
        // The mic end of the meeting pill mutes the microphone.
        if machine.phase != .open, case .meeting = model.activity,
            SurfaceSizing.meetingMuteZone(in: model.surfaceRect, placement: layout.anchor).contains(location)
        {
            services.microphone.toggleMute()
            return
        }
        // The watch pill's stop button, where it's drawn.
        if machine.phase != .open, let zone = watchStopZone, zone.contains(location) {
            services.regionWatch.stopAndConfirm()
            return
        }
        // The rest of the meeting pill opens the call app's controls, when it has any. Only the
        // states already read count: Accessibility reads never run in a click.
        if machine.phase != .open, case .meeting = model.activity, model.contains(location) {
            if !services.meetingControls.states.isEmpty {
                model.meetingControlsOpen = true
                // The pointer is reaching for the buttons, not waiting to open the shelf.
                dwellTask?.cancel()
                dwellTask = nil
                return
            }
        }
        if model.contains(location) {
            if machine.phase != .open {
                pendingPress = true
                return
            }
            // Let text fields (notes, search) and Esc reach the shelf without activating
            // Wisp. Hover opens stay non-key so typing keeps going to the front app.
            panel.makeKey()
        } else if machine.phase == .open {
            send(.clickedOutside)
        }
    }

    /// A press on the closed shell that didn't turn into a drag opens it.
    func leftMouseUp(at location: CGPoint) {
        guard pendingPress else { return }
        pendingPress = false
        guard model.contains(location) else { return }
        if isOrb, machine.phase != .open, model.activity == nil, services.preferences.ringOnOrbClick {
            services.ring.show(at: CGPoint(x: layout.closedRect.midX, y: layout.closedRect.midY))
            return
        }
        if machine.phase != .open, !services.shelfWindow.opensUnderShell {
            activateWindow()
            return
        }
        if machine.phase != .open {
            showActivityView()
            send(.clicked)
        }
        if machine.phase == .open { panel.makeKey() }
    }

    /// The window has the shelf: a click on the shell brings it forward, on the clicked pill's
    /// own view when it has one.
    private func activateWindow() {
        guard let pill = pillView() else {
            services.shelfWindow.activateShell()
            return
        }
        services.shelfWindow.activateShell(view: pill.view, session: pill.session)
    }

    /// The press became a drag of the shell; hovering must not open the shelf mid-drag.
    func cancelPress() {
        pendingPress = false
        dwellTask?.cancel()
        dwellTask = nil
    }

    /// A press on the open shelf outside its pages, so pulling it may tear it off into the window.
    func ownsShelfGrab(at location: CGPoint) -> Bool {
        guard machine.phase == .open, !model.dragging, !model.editingHome else { return false }
        let insets = ShellMetrics.shelfInsets(notchStyle: model.isNotchStyle, notchHeight: model.notchHeight)
        return ShelfTearOff.mayStart(at: location, surface: model.surfaceRect, insets: insets)
    }

    /// What the open shelf shows, for the window it's torn off into.
    var shown: ShelfView { model.shownView }

    /// A press on the closed island that only Wisp received, so dragging it may move it.
    func ownsIslandPress(at location: CGPoint) -> Bool {
        pendingPress
            && IslandDrag.mayStart(
                at: location, layout: layout, shape: model.surfaceRect, panelTakesClicks: !panel.ignoresMouseEvents)
    }

    /// A click on a live pill opens that activity's own view, whatever the profile's Home
    /// holds: the agent pill opens the Agents widget on the session it showed. Pills with
    /// nothing more to show open the usual page. Closing goes back to where the shelf was.
    private func showActivityView() {
        guard let pill = pillView() else { return }
        if let session = pill.session { model.focusedSession = session }
        model.show(pill.view, fromPill: true)
    }

    /// The view a click on the live pill opens, and the agent session it showed; nil for pills
    /// with nothing more to show. The shelf window opens the same view.
    private func pillView() -> (view: ShelfView, session: String?)? {
        guard let activity = model.activity else { return nil }
        switch PillDestination(slot: services.activities.currentSlot) {
        case .home: return nil
        case .agents:
            guard case .agent(let status) = activity else { return (.widget(.agents), nil) }
            return (.widget(.agents), status.sessionID)
        case .timer: return (.widget(Self.timerWidget(for: activity)), nil)
        case .nowPlaying: return (.widget(.nowPlaying), nil)
        case .battery: return (.widget(.battery), nil)
        case .tray: return (.page(.tray), nil)
        case .downloads: return (.detail(.downloads), nil)
        case .regionWatch: return (.detail(.regionWatch), nil)
        case .externalDetails: return (.detail(.external), nil)
        }
    }

    /// The timer slot carries the plain timer or the Pomodoro; each has its own widget.
    private static func timerWidget(for activity: Activity) -> WidgetKind {
        switch activity {
        case .timer(let label, _), .timerDone(let label):
            label == TimerStore.timerLabel ? .timer : .pomodoro
        default: .timer
        }
    }

    /// Two fingers on the closed notch: down opens the shelf, up puts away a card or alert,
    /// and sideways on the music pill skips tracks. An open shelf ignores swipes, since its
    /// lists scroll.
    func scrolled(_ scroll: PointerMonitor.Scroll, at location: CGPoint) {
        if scroll.boundary { swipe.reset() }
        guard machine.phase != .open, model.contains(location),
            let direction = swipe.add(dx: scroll.dx, dy: scroll.dy)
        else { return }
        if direction == layout.edge.openingSwipe {
            if services.shelfWindow.opensUnderShell { send(.clicked) } else { services.shelfWindow.activateShell() }
            return
        }
        if direction == layout.edge.closingSwipe, dismissActivity() { return }
        guard model.activity == .media else { return }
        // Skipping runs along the edge: sideways on top and bottom, up and down on the sides.
        switch (layout.edge.isSide, direction) {
        case (false, .left), (true, .up): services.nowPlaying.previous()
        case (false, .right), (true, .down): services.nowPlaying.next()
        default: break
        }
    }

    func rightMouseDown(at location: CGPoint) {
        guard model.contains(location) else { return }
        NotchMenu.show(
            at: location,
            customiseHome: { [weak self] in self?.customiseHome() },
            openPage: { [weak self] page in self?.open(page: page) },
            form: model.form,
            forms: model.forms,
            setForm: { [weak self] form in self?.model.onSetForm(form) },
            openAsWindow: { [weak self] in
                guard let self else { return }
                self.services.shelfWindow.openAsWindow(view: self.model.shownView)
            },
            moveBack: layout.moved
                ? NotchMenu.MoveBack(spot: layout.placement.title) { [weak self] in self?.moveIslandBack() } : nil,
            services: services
        )
    }

    /// A file drag moved; open the drop tiles when it reaches the notch.
    func fileDragMoved(to location: CGPoint) {
        // A new drag right after the last must not be cut short by its end timer.
        dragEndTask?.cancel()
        let target = layout.hitRegion(for: model.surfaceRect).insetBy(dx: -24, dy: -24)
        let over = target.contains(location)
        // Files dragged to the closed orb open the ring, to drop them on an action.
        if isOrb, over, machine.phase != .open {
            if !services.ring.isVisible {
                services.ring.show(at: CGPoint(x: layout.closedRect.midX, y: layout.closedRect.midY), dropping: true)
            }
            return
        }
        if over, !model.dragging {
            model.dragging = true
            // So leaving again registers as an exit and the shelf closes.
            pointerInside = true
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
            // Hovering onto the card started the hover timer; opening the shelf now would
            // hide the reply field and leave the reply hanging.
            dwellTask?.cancel()
            dwellTask = nil
            updateClickThrough()
            panel.makeKey()
        } else {
            services.notifications.openApp(for: item)
            services.activities.remove(.notification)
        }
        return true
    }

    private func endReply() {
        model.replyingTo = nil
        model.replyDraft = ""
        panel.resignKey()
        updateClickThrough()
    }

    /// Esc on a solo view steps back (to the grid, or to the page a pill's view came from)
    /// rather than closing the shelf.
    func leaveSoloWidget() -> Bool {
        guard machine.phase == .open, model.soloWidget != nil || model.activityDetail != nil else { return false }
        model.leaveSolo()
        return true
    }

    /// A profile switch picks the page the shelf opens on; an open shelf stays put.
    func setRestingPage(_ page: ShelfPage) {
        guard machine.phase != .open else { return }
        model.page = page
    }

    func open(page: ShelfPage) {
        guard services.shelfWindow.opensUnderShell else {
            services.shelfWindow.activateShell(view: .page(page))
            return
        }
        model.page = page
        if machine.phase != .open { send(.hotkey) }
    }

    func open(widget: WidgetKind) {
        guard services.shelfWindow.opensUnderShell else {
            services.shelfWindow.activateShell(view: .widget(widget))
            return
        }
        model.returnPage = model.page
        model.page = .widgets
        model.soloWidget = widget
        if machine.phase != .open { send(.hotkey) }
    }

    /// Another account is in front: the panel goes until this one is back.
    func suspend() {
        panel.orderOut(nil)
    }

    func resume() {
        panel.orderFrontRegardless()
    }

    func tearDown() {
        // A display unplugged mid-reply must not leave notifications held back forever.
        if isReplying { services.endReply(sentText: nil) }
        dwellTask?.cancel()
        closeTask?.cancel()
        dragEndTask?.cancel()
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        panel.orderOut(nil)
        panel.close()
    }

    /// Puts a dragged island back on its spot (the right-click menu's Form › "Move back").
    private func moveIslandBack() {
        let from = CGPoint(x: layout.closedRect.midX, y: layout.closedRect.midY)
        dismiss()
        settle(from: from)
        services.preferences.moveIslandBack(screenUUID)
    }

    private func customiseHome() {
        guard services.shelfWindow.opensUnderShell else {
            services.shelfWindow.customiseHome()
            return
        }
        model.page = .home
        model.homeSnapshot = (
            services.preferences.homeLayout, services.preferences.enabledWidgets, services.preferences.homeProfile
        )
        model.editingHome = true
        if machine.phase != .open { send(.hotkey) }
    }

    private func syncSettings() {
        let preferences = services.preferences
        // While the window has the shelf, hovering the shell mustn't open a second one.
        machine.opensOnHover = preferences.openTrigger == .hover && services.shelfWindow.opensUnderShell
        machine.closing = preferences.shelfClosing
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
            // Hovering onto an approval card is reaching for its buttons, not opening the shelf;
            // the same goes for a reply in progress.
            if showsApproval || isReplying { break }
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
        updateCardHover()
        // Click-through while closed, so the menu bar under the panel keeps working.
        updateClickThrough()

        if !wasOpen, machine.phase == .open {
            services.tray.pruneMissing()
            services.sounds.play(.open)
        }
        if wasOpen, machine.phase != .open { services.sounds.play(.close) }
        if machine.phase == .open, machine.pinned {
            // Keyboard-opened: take key status (without activating the app) so Esc reaches us.
            panel.makeKey()
        }
        if wasOpen, machine.phase == .closed {
            panel.resignKey()
            model.editingHome = false
            model.soloWidget = nil
            model.activityDetail = nil
            // The next plain click opens where it used to, not on the activity's view.
            if let returnPage = model.returnPage {
                model.page = returnPage
                model.returnPage = nil
            }
            model.dragging = false
            // Re-sync with the smaller closed region so the next hover is detected cleanly, and
            // so click-through doesn't wait for the pointer to move.
            pointerInside = model.contains(NSEvent.mouseLocation)
            resyncPointer()
        }
    }

    /// Re-reads where the pointer is after the shape changed under it, so a shell that moved
    /// or shrank away neither keeps eating clicks meant for the window below nor stays peeking.
    /// Entering is left to the next pointer move, so a shape landing under the pointer doesn't
    /// start the hover timer.
    private func resyncPointer() {
        let mouse = NSEvent.mouseLocation
        let closed = machine.phase != .open
        pointerOverBubble = closed && model.bubble(at: mouse) != nil
        pointerOverIsland = closed && IslandDrag.ownsPointer(at: mouse, layout: layout, shape: model.surfaceRect)
        if pointerInside, !model.contains(mouse), !model.dragging {
            pointerInside = false
            scheduleControlsCollapse(pointerInside: false)
            send(.pointerExited)
            return
        }
        updateClickThrough()
    }
}
