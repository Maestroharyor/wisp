import AppKit
import OSLog
import Observation
import SwiftUI
import WispCore

/// What the ring view draws: the set for the app in front, where the pointer is, and which
/// segment's sub-ring is open.
@MainActor
@Observable
final class RingModel {
    var set = RingConfig.defaults.standard
    /// Where the ring was opened, in global coordinates, while it's open.
    var origin: CGPoint?
    var agentChoices: [RingChoice] = []
    var formChoices: [RingChoice] = []
    /// The newest files of each folder segment, by segment, filled in once they're listed.
    var folderChoices: [Int: [RingChoice]] = [:]
    /// The windows of each running app segment, by segment, when it has more than one.
    var windowChoices: [Int: [RingChoice]] = [:]
    /// How many windows each running app segment has, for the count on its icon.
    var windowCounts: [Int: Int] = [:]
    /// Formats the dragged files can become, fanned out around Transform in drop mode.
    var convertChoices: [RingChoice] = []
    /// A live picture of the hovered window, shown in the ring's middle.
    var preview: RingPreview?
    /// Apps running when the ring opened, for the dots under app segments.
    var running: Set<String> = []
    var frontmost: String?
    /// What's been typed on the open ring, and what it finds.
    var query = ""
    var results: [RingSearch.Result] = []
    var selectedResult = 0
    var hover: RingHit = .none
    var expanded: Int?
    /// Files being dragged over the ring; segments that can't take them dim.
    var dropping = false
    /// Drives the open and close motion: wedges fly out when it turns on and back in when off.
    var visible = false
    /// The segment just picked, lit while the ring closes.
    var picked: RingHit?
    /// The ring's centre, in the panel's own coordinates (y down).
    var centre: CGPoint = .zero
    /// How many of the slots are the ring's own; the rest are running apps filling free places.
    var pinnedCount = 0
    /// The icon being dragged to a new place, and where the pointer has it (y down).
    var lifted: Int?
    var liftPoint: CGPoint = .zero
    /// The lifted icon is far enough out to come off the ring when let go.
    var removing = false
    /// A word in the middle after rearranging ("Removed Safari").
    var hint: String?
    /// A removal can be put back: the middle reads Undo and clicking it does that.
    var canUndo = false

    /// The sub-ring entries of a segment: agent sessions for Agents, else its group.
    func subItems(of index: Int) -> [RingChoice] {
        guard set.slots.indices.contains(index) else { return [] }
        let slot = set.slots[index]
        if slot.action.kind == .agents { return agentChoices }
        if slot.action.kind == .form { return formChoices }
        if slot.action.kind == .folder { return folderChoices[index] ?? [] }
        if slot.action.kind == .transform, dropping, !convertChoices.isEmpty { return convertChoices }
        // A sub-ring the user set up for the segment comes first; windows fill an empty one.
        if slot.action.kind == .app, slot.group.isEmpty, let windows = windowChoices[index], !windows.isEmpty {
            return windows
        }
        return slot.group.enumerated().map { offset, action in
            RingChoice(id: "action:\(offset)", title: action.title, icon: action.icon)
        }
    }

    var expandedItems: [RingChoice] { expanded.map(subItems) ?? [] }

    func dot(for action: RingAction) -> RingRunState {
        RingRunState.dot(for: action, running: running, frontmost: frontmost)
    }
}

/// A window's picture for the ring's middle, with the title shown under it.
struct RingPreview {
    let image: CGImage
    let title: String
    /// Which window it is, so the same hover doesn't capture again.
    let key: String
}

/// The radial ring: opens at the pointer or around the orb, runs the segment picked, and
/// takes files dropped on segments that accept them.
@MainActor
final class RingController {
    private let services: AppServices
    private let model = RingModel()
    private var panel: RingPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var escapeMonitor: Any?
    private var openedAt = Date.now
    private var dropEndTask: Task<Void, Never>?
    private var dragOutTask: Task<Void, Never>?
    /// Folders still being listed, so a slow share isn't asked again on every opening.
    private var listing: Set<String> = []
    /// Counts window listings, so a late answer from an earlier opening is dropped.
    private var windowListings = 0
    /// Opened by holding a mouse button; letting go picks.
    private var holding = false
    /// Each running app segment's windows as Accessibility listed them, for previews.
    private var windowLists: [Int: (pid: pid_t, windows: [WindowSummary])] = [:]
    private let previews = WindowPreviewCapture()
    private var previewTask: Task<Void, Never>?
    private var previewImages: [String: CGImage] = [:]
    /// Screen Recording was already on when the ring opened; previews never ask for it.
    private var canPreview = false
    /// The square a preview is fitted into, in points: inside the ring's middle with room for
    /// the title under it.
    static let previewSide: CGFloat = 132
    private static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "ring")
    /// Where the press that opened the ring was, for telling a flick from a press.
    private var pressPoint: CGPoint = .zero

    private static let side = (RingGeometry.subOuter + RingGeometry.margin * 2) * 2

    init(services: AppServices) {
        self.services = services
        services.appCatalog.onChange = { [weak self] in self?.search() }
    }

    /// Showing and not on its way out. A ring gone see-through while a file is dragged out of
    /// it counts as gone, so the next press opens it again.
    var isVisible: Bool { (panel?.isVisible ?? false) && closeTask == nil && dragOutTask == nil }

    /// Where the open ring was opened, observed, so an orb it opened over can step aside.
    var openAround: CGPoint? { model.origin }
    private var closeTask: Task<Void, Never>?
    /// A file drag is under way somewhere on screen.
    private var fileDragging = false

    /// Opens the ring centred near `point`, in global AppKit coordinates.
    func show(at point: CGPoint, holding: Bool = false, dropping: Bool = false) {
        guard let screen = Self.screen(nearest: point) else { return }
        dropEndTask?.cancel()
        dropEndTask = nil
        services.orbDock.hide()
        RingIconCache.shared.retryMissing()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        loadSet(front: front)
        removed = nil
        model.canUndo = false
        model.hint = nil
        model.lifted = nil
        model.agentChoices = RingAgentChoices.choices(for: agentEntries())
        let state = services.formUnderPointer()
        model.formChoices = RingFormChoices.choices(current: state.form, systemIsland: state.systemIsland)
        model.running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        model.frontmost = front
        listFolders()
        listWindows()
        model.convertChoices = []
        if dropping {
            model.set = RingDropSet.withTransform(model.set)
            offerFormats(for: Self.draggedFiles())
        }
        resetPreviews()
        canPreview = !dropping && services.preferences.ringAppWindows && CGPreflightScreenCaptureAccess()
        markTip(.open)
        model.hover = .none
        model.expanded = nil
        model.picked = nil
        model.query = ""
        model.results = []
        model.selectedResult = 0
        pressPoint = point
        model.origin = point
        services.appCatalog.refreshIfStale()
        closeTask?.cancel()
        closeTask = nil
        // Start folded, then open on the next pass so the wedges animate out.
        model.visible = false
        model.dropping = dropping
        self.holding = holding
        openedAt = .now

        let centre = RingGeometry.fittedCentre(
            point, in: screen.visibleFrame, avoidsTopCentre: screen.hasSystemIsland(services.preferences.islandSetting))
        // Pushed in from an edge, the ring takes the pointer to its middle so hovers and flicks
        // start there. Not during a file drag, which the move would disturb.
        if !dropping, let target = RingGeometry.pointerMove(from: point, to: centre) {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            CGWarpMouseCursorPosition(
                RegionGeometry.flipped(CGRect(origin: target, size: .zero), primaryHeight: primaryHeight).origin)
            // A warp pauses pointer movement briefly; reconnecting ends that pause at once.
            CGAssociateMouseAndMouseCursorPosition(1)
            pressPoint = target
        }
        // The ring is laid out at the standard size and drawn scaled; the panel takes the scaled size.
        let side = Self.side * services.preferences.ringLook.clamped().size
        let frame = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        model.centre = CGPoint(x: Self.side / 2, y: Self.side / 2)

        let panel = panel ?? makePanel()
        self.panel = panel
        dragOutTask?.cancel()
        dragOutTask = nil
        panel.ignoresMouseEvents = false
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        Task { @MainActor [model] in model.visible = true }
        if !dropping { panel.makeKey() }
        startMonitors()
    }

    /// The ring for the app in front, with running apps in its free places when that's on.
    private func loadSet(front: String?) {
        let shown = Self.shownSet(preferences: services.preferences, front: front)
        model.set = shown.set
        model.pinnedCount = shown.pinned
    }

    /// The ring as it shows for the app in front: its own slots, then running apps in the free
    /// places when that's on. The orb's dock reads the same list, so the two always agree.
    static func shownSet(preferences: Preferences, front: String?) -> (set: RingSet, pinned: Int) {
        let set = preferences.ringConfig.set(forFrontApp: front)
        guard preferences.ringShowsRunning else { return (set, set.slots.count) }
        let own = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id)
        }
        let filled = RingSet(
            id: set.id, name: set.name, slots: RingRunning.fill(set.slots, running: running), bundleIDs: set.bundleIDs)
        return (filled, set.slots.count)
    }

    /// The display a point is on. `frame.contains` leaves out a frame's top edge, where the
    /// pointer and an orb at the very top sit, so the nearest display wins.
    private static func screen(nearest point: CGPoint) -> NSScreen? {
        NSScreen.screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }

    /// A file drag is moving; one that ended moments ago doesn't take the ring away under it.
    func dragMoved() {
        fileDragging = true
        guard model.dropping else { return }
        dropEndTask?.cancel()
        dropEndTask = nil
    }

    /// A file drag ended; give a drop on the ring time to land, then put the ring away.
    func dragEnded() {
        fileDragging = false
        guard model.dropping else { return }
        dropEndTask?.cancel()
        dropEndTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Folds the ring back into its centre, then takes the panel away.
    func hide() {
        dropEndTask?.cancel()
        guard let panel, panel.isVisible, closeTask == nil else { return }
        stopMonitors()
        holding = false
        resetPreviews()
        model.visible = false
        model.origin = nil
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            panel.orderOut(nil)
            self.model.dropping = false
            self.closeTask = nil
        }
    }

    /// The shortcut opens the ring; mid file drag it opens ready to take the files on an action.
    func toggle(at point: CGPoint) {
        if isVisible { hide() } else { show(at: point, dropping: fileDragging) }
    }

    /// The button's release was lost (its tap was switched off mid-hold): the ring stays open
    /// for clicking, and a click elsewhere puts it away again.
    func cancelHold() {
        holding = false
    }

    /// The mouse button that opened the ring went up: a hold picks, a quick press stays open.
    func released(at point: CGPoint) {
        guard holding, isVisible else { return }
        holding = false
        // Typing took over from the mouse: the search card decides, not where the button went up.
        guard model.query.isEmpty else { return }
        let centre = panel.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? pressPoint
        let look = services.preferences.ringLook
        let outcome = RingFlick.release(
            after: Date.now.timeIntervalSince(openedAt), from: look.unscaled(pressPoint, around: centre),
            to: look.unscaled(point, around: centre), centre: centre,
            hit: hit(atGlobal: point), slots: model.set.slots.count, expanded: model.expanded,
            subItems: model.expandedItems.count)
        switch outcome {
        case .stayOpen: break
        case .pick(let hit): pick(hit, files: [])
        case .close: hide()
        }
    }

    /// The pointer moved while a button holds the ring open; the panel doesn't see it then.
    func pointerMoved(to point: CGPoint) {
        guard isVisible, let frame = panel?.frame else { return }
        let scale = services.preferences.ringLook.clamped().size
        hovered(hit(atGlobal: point), distance: hypot(point.x - frame.midX, point.y - frame.midY) / scale)
    }

    func hovered(_ hit: RingHit, distance: CGFloat) {
        // Moving on to something else clears the word left by rearranging.
        if hit != model.hover, hit != .none {
            model.hint = nil
            Feedback.selection()
        }
        model.hover = hit
        let before = model.expanded
        model.expanded = RingInteraction.expanded(
            current: model.expanded, hit: hit, distance: distance,
            hasSubItems: { [model] in !model.subItems(of: $0).isEmpty })
        if let index = model.expanded, index != before, model.windowChoices[index]?.isEmpty == false {
            markTip(.windows)
        }
        updatePreview()
    }

    /// Runs what was picked; files come from a drop. Apps dropped on the ring (not on a folder)
    /// are added to it instead.
    func pick(_ hit: RingHit, files: [URL]) {
        if case .slot(let index) = hit, !model.set.slots.indices.contains(index) { return }
        // Right after a removal the middle is an Undo button, not the shelf.
        if hit == .centre, files.isEmpty, removed != nil {
            undoRemoval()
            return
        }
        let target: RingAction.Kind? =
            if case .slot(let index) = hit { model.set.slots[index].action.kind } else { nil }
        let onSub: Bool = if case .sub = hit { true } else { false }
        if !onSub, RingPinDrop.pins(paths: files.map(\.path), onto: target) {
            let index: Int = if case .slot(let slot) = hit { min(slot, model.pinnedCount) } else { model.pinnedCount }
            pin(files, at: index)
            return
        }
        let outcome = RingInteraction.outcome(
            of: hit, slots: model.set.slots, expanded: model.expanded, subItemCount: model.expandedItems.count,
            hasFiles: !files.isEmpty,
            hasChoices: { [model] in !model.subItems(of: $0).isEmpty })
        if case .expand(let index) = outcome {
            model.expanded = index
            return
        }
        let slots = model.set.slots
        if case .slot = hit { model.picked = hit }
        if case .sub = hit { model.picked = hit }
        let agentChoices = model.agentChoices
        let formChoices = model.formChoices
        let folderChoices = model.expandedItems
        let windowChoices = model.windowChoices
        let convertChoices = model.convertChoices
        let dropping = model.dropping
        hide()
        switch outcome {
        case .openShelf: services.openShelf(.home)
        // Files dropped on the middle go to the tray, like dropping them on the notch.
        case .keepFiles: services.tray.add(files)
        case .run(let index): run(slots[index].action, files: files)
        case .runSub(let index, let item):
            if slots[index].action.kind == .agents {
                runAgentChoice(agentChoices[safe: item])
            } else if slots[index].action.kind == .form {
                runFormChoice(formChoices[safe: item])
            } else if slots[index].action.kind == .folder {
                openFolderChoice(folderChoices[safe: item], in: slots[index].action, files: files)
            } else if slots[index].action.kind == .transform, dropping, !convertChoices.isEmpty {
                runConvertChoice(convertChoices[safe: item], files: files)
            } else if slots[index].action.kind == .app, slots[index].group.isEmpty,
                let windows = windowChoices[index], !windows.isEmpty
            {
                openWindowChoice(windows[safe: item], of: slots[index].action, files: files)
            } else if let action = slots[index].group[safe: item] {
                run(action, files: files)
            }
        case .expand, .close: break
        }
    }

    private func hit(atGlobal point: CGPoint) -> RingHit {
        guard let frame = panel?.frame else { return .none }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return RingGeometry.hit(
            services.preferences.ringLook.unscaled(point, around: centre), centre: centre, slots: model.set.slots.count,
            expanded: model.expanded,
            subItems: model.expandedItems.count)
    }

    // MARK: Arranging

    /// The ring as it was before the last removal, for ⌘Z.
    private var removed: [RingSlot]?

    /// An icon is being dragged on the open ring (a click, not a held button): it follows the
    /// pointer, and is marked for removal once it's far enough out.
    func lift(from hit: RingHit, to point: CGPoint) {
        guard !holding, model.query.isEmpty, !model.dropping else { return }
        if model.lifted == nil {
            guard case .slot(let index) = hit, model.set.slots.indices.contains(index) else { return }
            model.lifted = index
            model.expanded = nil
            model.hint = nil
        }
        model.liftPoint = point
        let pinned = (model.lifted ?? 0) < model.pinnedCount
        model.removing = pinned && distance(fromCentre: point) > RingArrange.removeBeyond
    }

    /// The dragged icon was let go: moved to where it points, taken off when far out, and a
    /// running app dropped anywhere on the ring is pinned there.
    func land(at point: CGPoint) {
        guard let from = model.lifted else { return }
        model.lifted = nil
        model.removing = false
        let pinned = Array(model.set.slots.prefix(model.pinnedCount))
        let action = model.set.slots[safe: from]?.action
        if distance(fromCentre: point) > RingArrange.removeBeyond {
            guard from < model.pinnedCount, let action else { return }
            removed = pinned
            model.canUndo = true
            save(RingArrange.remove(pinned, at: from))
            model.hint = "Removed \(action.title)"
            return
        }
        // y runs down in the view; angles run clockwise from 12 o'clock.
        let angle = atan2(point.x - model.centre.x, model.centre.y - point.y) * 180 / .pi
        let to = RingArrange.index(at: angle, count: model.set.slots.count)
        if from < model.pinnedCount {
            guard to != from else { return }
            save(RingArrange.move(pinned, from: from, to: min(to, max(model.pinnedCount - 1, 0))))
            Feedback.landed()
        } else if let action,
            case .added(let slots) = RingArrange.insert(
                [action], into: pinned, at: min(to, model.pinnedCount))
        {
            save(slots)
            Feedback.landed()
            model.hint = "Kept \(action.title) on the ring"
        }
    }

    /// Puts back what the last removal took.
    private func undoRemoval() {
        guard let removed else { return }
        self.removed = nil
        model.canUndo = false
        save(removed)
        model.hint = nil
    }

    /// Apps dropped on the ring from Finder or the Dock join it where they land.
    private func pin(_ urls: [URL], at index: Int) {
        let actions = urls.compactMap { url -> RingAction? in
            guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            return RingAction(.app, value: id, label: name)
        }
        // From the ring as saved: during a drag the one shown may have lent a place to Transform.
        let saved = Self.shownSet(preferences: services.preferences, front: model.frontmost).set
        let pinned = Array(saved.slots.prefix(model.pinnedCount))
        let text: String
        switch RingArrange.insert(actions, into: pinned, at: index) {
        case .added(let slots):
            save(slots)
            text =
                actions.count == 1 ? "Added \(actions[0].title) to the ring" : "Added \(actions.count) apps to the ring"
        case .alreadyThere: text = "Already on the ring"
        case .full: text = "The ring is full"
        }
        model.hint = text
        // A ring opened by a drag closes when the drag ends, so the answer shows under the notch too.
        if model.dropping {
            services.activities.post(.notice(symbol: "circle.circle", text: text), slot: .notice, duration: 2)
        }
    }

    /// Saves the ring's own slots to the set it came from and shows the result at once.
    private func save(_ pinned: [RingSlot]) {
        var config = services.preferences.ringConfig
        if config.standard.id == model.set.id {
            config.standard.setSlots(pinned)
        } else if let index = config.perApp.firstIndex(where: { $0.id == model.set.id }) {
            config.perApp[index].setSlots(pinned)
        } else {
            return
        }
        services.preferences.ringConfig = config
        loadSet(front: model.frontmost)
        model.hover = .none
        model.expanded = nil
        // Sub-rings are kept by position, which just changed.
        listFolders()
        listWindows()
    }

    private func distance(fromCentre point: CGPoint) -> CGFloat {
        hypot(point.x - model.centre.x, point.y - model.centre.y)
    }

    private func agentEntries() -> [RingAgentEntry] {
        let agents = services.agents
        // Questions need an answer picked, not Allow, so they stay on their card.
        let waiting = Dictionary(
            agents.approvals.filter { $0.questions.isEmpty }.map { ($0.sessionID, $0.id) },
            uniquingKeysWith: { first, _ in first })
        return agents.sessions.list.map { session in
            RingAgentEntry(sessionID: session.id, project: session.project, approvalID: waiting[session.id])
        }
    }

    /// Lists each folder segment's newest files off the main thread; a folder that's slow to
    /// list (a network share) just has no sub-ring until it answers.
    private func listFolders() {
        model.folderChoices = [:]
        let paths = Set(model.set.slots.compactMap { $0.action.kind == .folder ? $0.action.value : nil })
        for path in paths where !path.isEmpty && !listing.contains(path) {
            listing.insert(path)
            Task { [weak self] in
                let entries = await Self.entries(in: path)
                guard let self else { return }
                self.listing.remove(path)
                // Whichever opening is showing now gets it, so a listing that outlasts a quick
                // close and reopen still lands, on every segment for that folder.
                let choices = FolderPeek.choices(for: FolderPeek.newest(entries))
                for (index, slot) in self.model.set.slots.enumerated()
                where slot.action.kind == .folder && slot.action.value == path {
                    self.model.folderChoices[index] = choices
                }
            }
        }
    }

    /// Lists the windows of each running app on the ring, through Accessibility. Nothing is
    /// asked for when Accessibility isn't granted; the segments just have no window sub-ring.
    private func listWindows() {
        model.windowChoices = [:]
        model.windowCounts = [:]
        windowLists = [:]
        windowListings += 1
        let listing = windowListings
        guard services.preferences.ringAppWindows, AccessibilityPermission.isTrusted else { return }
        for (index, slot) in model.set.slots.enumerated() where slot.action.kind == .app && slot.group.isEmpty {
            guard let id = slot.action.value,
                let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
            else { continue }
            let pid = app.processIdentifier
            let name = slot.action.title
            Task { [weak self] in
                let windows = await AXWindows.list(pid: pid)
                // Only for this opening, and never under a sub-ring that's already open, so what's
                // under the pointer doesn't change.
                guard let self, self.windowListings == listing else { return }
                self.windowLists[index] = (pid, windows)
                self.model.windowCounts[index] = windows.count
                guard self.model.expanded != index else { return }
                self.model.windowChoices[index] = AppWindows.choices(appName: name, windows: windows)
            }
        }
    }

    /// A window from an app's sub-ring: brought forward, out of the Dock if minimised, with its
    /// app. The count of the rest opens the app; files dropped anywhere on it open with the app.
    private func openWindowChoice(_ choice: RingChoice?, of app: RingAction, files: [URL]) {
        guard files.isEmpty, let target = choice.flatMap(AppWindows.target(of:)),
            let id = app.value, let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        else {
            run(app, files: files)
            return
        }
        let pid = running.processIdentifier
        Task { [weak self] in
            _ = await AXWindows.raise(pid: pid, target: target)
            self?.run(app, files: [])
        }
    }

    /// On a dispatch queue rather than the shared task pool: listing a dead network share can
    /// block for a long time, and it mustn't hold up Wisp's other background work.
    private nonisolated static func entries(in path: String) async -> [FolderEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: listEntries(in: path))
            }
        }
    }

    private nonisolated static func listEntries(in path: String) -> [FolderEntry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isHiddenKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: keys)) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return FolderEntry(
                name: url.lastPathComponent, path: url.path,
                modified: values?.contentModificationDate ?? .distantPast,
                isHidden: values?.isHidden ?? false)
        }
    }

    /// A file from a folder's sub-ring: opens it. Files dropped on it open with it when it's an
    /// app, and otherwise go into the folder, as a drop on the folder itself would.
    private func openFolderChoice(_ choice: RingChoice?, in folder: RingAction, files: [URL]) {
        guard let path = choice.flatMap(FolderPeek.path(of:)) else { return }
        let url = URL(fileURLWithPath: path)
        if files.isEmpty {
            NSWorkspace.shared.open(url)
        } else if url.pathExtension == "app" {
            NSWorkspace.shared.open(files, withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
        } else if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            // A folder inside takes them, as it would in Finder.
            run(RingAction(.folder, value: path), files: files)
        } else {
            run(folder, files: files)
        }
    }

    /// A file is being dragged out of a folder's sub-ring. The ring goes invisible rather than
    /// away, since taking the panel away would end the drag; it leaves once the button is up.
    func draggingOut() {
        guard let panel else { return }
        stopMonitors()
        holding = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        // The ring is gone from view, so the orb under it comes back now.
        model.origin = nil
        dragOutTask?.cancel()
        dragOutTask = Task { [weak self] in
            while !Task.isCancelled, NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, let self else { return }
            self.dragOutTask = nil
            panel.orderOut(nil)
            panel.ignoresMouseEvents = false
            panel.alphaValue = 1
            self.model.visible = false
            self.model.origin = nil
            self.model.dropping = false
        }
    }

    private func runFormChoice(_ choice: RingChoice?) {
        guard let id = choice?.id, id.hasPrefix("form:"), let form = FormFactor(rawValue: String(id.dropFirst(5)))
        else { return }
        services.setForm(form)
    }

    private func runAgentChoice(_ choice: RingChoice?) {
        guard let choice else { return }
        let parts = choice.id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "allow", "deny":
            if let id = UUID(uuidString: parts[1]) { services.agents.answer(id, allow: parts[0] == "allow") }
        case "focus":
            services.agents.focus(session: parts[1])
        default:
            break
        }
    }

    private func run(_ action: RingAction, files: [URL]) {
        RingActionRunner.run(action, files: files, services: services)
    }

    private func startMonitors() {
        stopMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let characters = event.characters ?? ""
            let modified = !event.modifierFlags.intersection([.command, .control]).isEmpty
            let undo = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z"
            let handled = MainActor.assumeIsolated {
                if undo, let self, self.removed != nil {
                    self.undoRemoval()
                    return true
                }
                return self?.handleKey(keyCode, characters: characters, modified: modified) ?? false
            }
            return handled ? nil : event
        }
        // A ring opened by a file drag never takes the keyboard, so Esc, and the numbers of the
        // formats fanned out around Transform, are watched for globally.
        if model.dropping {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = event.keyCode
                let number = event.charactersIgnoringModifiers.flatMap(Int.init)
                MainActor.assumeIsolated {
                    if keyCode == KeyCodes.escape {
                        self?.hide()
                    } else if let number {
                        self?.convertDragged(choice: number - 1)
                    }
                }
            }
        }
        // A click anywhere else puts the ring away.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.holding else { return }
                self.hide()
            }
        }
    }

    /// Esc closes the ring (or clears what's typed), 1 to 8 pick a segment, the arrows move
    /// round it and Return picks; typing anything else searches the ring and the Mac's apps.
    private func handleKey(_ keyCode: UInt16, characters: String, modified: Bool) -> Bool {
        guard isVisible else { return false }
        let command = RingTyping.command(
            keyCode: keyCode, characters: characters, modified: modified, query: model.query)
        switch command {
        case .ignore:
            // Shortcuts go on to other apps; any other key is the ring's while it's open, so a
            // stray one doesn't beep.
            return !modified
        case .close:
            hide()
        case .clearQuery:
            model.query = ""
            search()
        case .type(let text):
            model.query = text
            model.results = []
            markTip(.search)
            updatePreview()
            search()
        case .moveResult(let step):
            guard !model.results.isEmpty else { break }
            model.selectedResult = min(max(model.selectedResult + step, 0), model.results.count - 1)
        case .move(let key):
            let cursor = RingKeys.move(
                key, from: RingCursor(hover: model.hover, expanded: model.expanded), slots: model.set.slots.count
            ) { [model] in model.subItems(of: $0).count }
            model.hover = cursor.hover
            model.expanded = cursor.expanded
            updatePreview()
        case .pickSlot(let index):
            guard index < model.set.slots.count else { return true }
            markTip(.number)
            pick(.slot(index), files: [])
        case .submit:
            submit()
        }
        return true
    }

    private func submit() {
        if !model.query.isEmpty {
            pickResult(model.selectedResult)
            return
        }
        switch model.hover {
        case .slot, .sub: pick(model.hover, files: [])
        case .centre, .none: break
        }
    }

    /// Runs a search result: something on the ring, or an app.
    func pickResult(_ index: Int) {
        guard model.results.indices.contains(index) else { return }
        let action = model.results[index].action
        Feedback.selection()
        hide()
        run(action, files: [])
    }

    #if DEBUG
        /// Types `text` as key presses; a newline presses Return.
        func debugType(_ text: String) {
            for character in text {
                if character == "\n" {
                    _ = handleKey(RingTyping.returnKey, characters: "\r", modified: false)
                } else {
                    _ = handleKey(0, characters: String(character), modified: false)
                }
            }
        }
    #endif

    private func search() {
        let apps = services.appCatalog.apps
        let names = Dictionary(apps.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { first, _ in first })
        // An app put on the ring without a name is found by the name it has on the Mac.
        let ring = model.set.slots.flatMap { [$0.action] + $0.group }.map { action in
            guard action.kind == .app, action.label == nil, let name = action.value.flatMap({ names[$0] }) else {
                return action
            }
            return RingAction(.app, value: action.value, label: name)
        }
        let selected = model.results[safe: model.selectedResult]?.id
        model.results = RingSearch.results(model.query, ring: ring, apps: apps)
        // A list that arrives while you're choosing keeps your place.
        model.selectedResult = selected.flatMap { id in model.results.firstIndex { $0.id == id } } ?? 0
    }

    private func stopMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        keyMonitor = nil
        clickMonitor = nil
        escapeMonitor = nil
    }

    private func makePanel() -> RingPanel {
        let side = Self.side
        let panel = RingPanel(
            contentRect: CGRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onResignKey = { [weak self] in
            guard let self, !self.holding, !self.model.dropping else { return }
            self.hide()
        }
        let view = RingView(
            model: model,
            onHover: { [weak self] hit, distance in self?.hovered(hit, distance: distance) },
            onPick: { [weak self] hit, files in self?.pick(hit, files: files) },
            onPickResult: { [weak self] index in self?.pickResult(index) },
            onDragOut: { [weak self] in self?.draggingOut() },
            onLift: { [weak self] hit, point in self?.lift(from: hit, to: point) },
            onLand: { [weak self] point in self?.land(at: point) })
        panel.contentView = NSHostingView(
            rootView: ScaledRing(preferences: services.preferences, side: Self.side) { view })
        return panel
    }
}

/// Takes the keyboard (Esc, digits) without activating Wisp.
final class RingPanel: NSPanel {
    var onResignKey: @MainActor () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        MainActor.assumeIsolated { onResignKey() }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The ring laid out at its standard size and drawn at the size chosen in Settings, so its
/// geometry and hit-testing stay in standard points.
private struct ScaledRing<Content: View>: View {
    let preferences: Preferences
    let side: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let scale = preferences.ringLook.clamped().size
        content
            .frame(width: side, height: side)
            .scaleEffect(scale)
            .frame(width: side * scale, height: side * scale)
    }
}

// MARK: Previews, converting and the checklist

extension RingController {
    private struct PreviewRequest: Sendable {
        let pid: pid_t
        let window: WindowSummary
        let title: String
        let key: String
    }

    /// The window under the pointer: one in an app's sub-ring, or the app's front window when
    /// its segment is hovered.
    private func previewRequest() -> PreviewRequest? {
        let index: Int
        let place: Int
        switch model.hover {
        case .slot(let slot):
            guard let listed = windowLists[slot], let front = listed.windows.firstIndex(where: { !$0.isMinimised })
            else { return nil }
            index = slot
            place = front
        case .sub(let item):
            guard let slot = model.expanded, let listed = windowLists[slot],
                let target = model.windowChoices[slot]?[safe: item].flatMap(AppWindows.target(of:)),
                let found = AppWindows.match(target, in: listed.windows)
            else { return nil }
            index = slot
            place = found
        case .centre, .none:
            return nil
        }
        guard let listed = windowLists[index], let window = listed.windows[safe: place] else { return nil }
        let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? model.set.slots[safe: index]?.action.title ?? ""
        return PreviewRequest(pid: listed.pid, window: window, title: title, key: "\(listed.pid):\(place)")
    }

    /// Shows the hovered window's picture, captured after a short pause so sweeping across the
    /// ring doesn't capture every window on the way.
    fileprivate func updatePreview() {
        guard canPreview, model.query.isEmpty, let request = previewRequest() else {
            previewTask?.cancel()
            previewTask = nil
            model.preview = nil
            return
        }
        if model.preview?.key == request.key { return }
        previewTask?.cancel()
        if let image = previewImages[request.key] {
            model.preview = RingPreview(image: image, title: request.title, key: request.key)
            return
        }
        model.preview = nil
        let previews = previews
        let pid = request.pid
        let window = request.window
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let image: CGImage?
            do {
                image = try await ScreenSnapshot.firstOf(timeout: .seconds(2)) {
                    try await previews.image(pid: pid, window: window, side: Self.previewSide)
                }
            } catch is CancellationError {
                return
            } catch {
                // Without this a missing grant or a capture error looks the same as no window.
                Self.log.error("Window preview failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard !Task.isCancelled, let self, let image else { return }
            self.previewImages[request.key] = image
            self.model.preview = RingPreview(image: image, title: request.title, key: request.key)
            self.markTip(.windows)
        }
    }

    /// Pictures are only kept while the ring is open.
    fileprivate func resetPreviews() {
        previewTask?.cancel()
        previewTask = nil
        previewImages = [:]
        model.preview = nil
        let previews = previews
        Task { await previews.reset() }
    }

    /// The files being dragged right now, read from the drag pasteboard (their addresses only).
    fileprivate static func draggedFiles() -> [URL] {
        let items = NSPasteboard(name: .drag).pasteboardItems ?? []
        return items.compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:)) }.filter(\.isFileURL)
    }

    /// The formats around Transform for the dragged files. A video with no sound can't become
    /// M4A; that takes a moment to find out, so the list is corrected once it's known, unless the
    /// formats are already fanned out under the pointer.
    fileprivate func offerFormats(for files: [URL]) {
        let exts = files.map(\.pathExtension)
        model.convertChoices = ConvertTargets.choices(for: ConvertTargets.formats(forExtensions: exts))
        let videos = files.filter { ConvertTargets.kind(ofExtension: $0.pathExtension) == .video }
        guard !videos.isEmpty else { return }
        Task { [weak self] in
            let sound = await MediaConvert.haveSound(videos, within: .milliseconds(300))
            guard let self, self.model.dropping, sound == false else { return }
            if let expanded = self.model.expanded, self.model.set.slots[safe: expanded]?.action.kind == .transform {
                return
            }
            self.model.convertChoices = ConvertTargets.choices(
                for: ConvertTargets.formats(forExtensions: exts, videosHaveSound: false))
        }
    }

    /// A number pressed mid drag while the formats are fanned out converts the dragged files.
    fileprivate func convertDragged(choice index: Int) {
        guard model.dropping, let expanded = model.expanded,
            model.set.slots[safe: expanded]?.action.kind == .transform,
            let choice = model.convertChoices[safe: index], ConvertTargets.format(of: choice) != nil
        else { return }
        let files = Self.draggedFiles()
        guard !files.isEmpty else { return }
        markTip(.number)
        hide()
        runConvertChoice(choice, files: files)
    }

    /// A format from around Transform: converts the files straight to the tray. "More…" opens
    /// the Transform panel with them.
    fileprivate func runConvertChoice(_ choice: RingChoice?, files: [URL]) {
        guard let choice else { return }
        guard let format = ConvertTargets.format(of: choice) else {
            services.openTransform(files)
            return
        }
        guard !files.isEmpty else { return }
        markTip(.convert)
        let count = files.count
        services.activities.post(
            .notice(
                symbol: "arrow.triangle.2.circlepath",
                text: "Converting \(count == 1 ? "1 file" : "\(count) files") to \(format.title)…"),
            slot: .notice, duration: 2)
        Task { [services] in
            let outcome = await MediaConvert.run(format, urls: files)
            services.tray.add(outcome.outputs)
            let done = outcome.outputs.count
            let text =
                outcome.problem.map { done == 0 ? $0 : "\($0). \(done) done, in the tray" }
                ?? "\(done == 1 ? "1 file" : "\(done) files") converted to \(format.title), in the tray"
            services.activities.post(
                .notice(symbol: done == 0 ? "exclamationmark.triangle" : "checkmark.circle", text: text), slot: .notice,
                duration: 3)
        }
    }

    /// Ticks a step off the "Try the ring" checklist, saving only on a change.
    fileprivate func markTip(_ step: RingTips.Step) {
        var tips = services.preferences.ringTips
        guard tips.mark(step) else { return }
        services.preferences.ringTips = tips
    }
}

#if DEBUG
    extension RingController {
        /// "slot|path": gives an app segment three windows and shows the image as its preview,
        /// for checking how they're drawn without granting Screen Recording.
        func debugPreview(_ text: String) {
            let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let slot = Int(parts[0]),
                let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: parts[1]) as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return }
            model.windowCounts[slot] = 3
            model.hover = .slot(slot)
            model.preview = RingPreview(image: image, title: "Project notes", key: "debug")
        }

        /// "format|path": converts the file as if it were dropped on that format.
        func debugConvert(_ text: String) {
            let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let format = ConvertFormat(rawValue: parts[0]) else { return }
            let choice = ConvertTargets.choices(for: [format])[0]
            runConvertChoice(choice, files: [URL(fileURLWithPath: parts[1])])
        }
    }
#endif
