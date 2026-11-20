import AppKit
import Observation
import SwiftUI
import WispCore

/// What the ring view draws: the set for the app in front, where the pointer is, and which
/// segment's sub-ring is open.
@MainActor
@Observable
final class RingModel {
    var set = RingConfig.defaults.standard
    var agentChoices: [RingChoice] = []
    var formChoices: [RingChoice] = []
    /// The newest files of each folder segment, by segment, filled in once they're listed.
    var folderChoices: [Int: [RingChoice]] = [:]
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

    /// The sub-ring entries of a segment: agent sessions for Agents, else its group.
    func subItems(of index: Int) -> [RingChoice] {
        guard set.slots.indices.contains(index) else { return [] }
        let slot = set.slots[index]
        if slot.action.kind == .agents { return agentChoices }
        if slot.action.kind == .form { return formChoices }
        if slot.action.kind == .folder { return folderChoices[index] ?? [] }
        return slot.group.enumerated().map { offset, action in
            RingChoice(id: "action:\(offset)", title: action.title, icon: action.icon)
        }
    }

    var expandedItems: [RingChoice] { expanded.map(subItems) ?? [] }

    func dot(for action: RingAction) -> RingRunState {
        RingRunState.dot(for: action, running: running, frontmost: frontmost)
    }
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
    private var openedAt = Date.now
    private var dropEndTask: Task<Void, Never>?
    private var dragOutTask: Task<Void, Never>?
    /// Folders still being listed, so a slow share isn't asked again on every opening.
    private var listing: Set<String> = []
    /// Opened by holding a mouse button; letting go picks.
    private var holding = false
    /// Where the press that opened the ring was, for telling a flick from a press.
    private var pressPoint: CGPoint = .zero

    private static let side = (RingGeometry.subOuter + RingGeometry.margin * 2) * 2

    init(services: AppServices) {
        self.services = services
        services.appCatalog.onChange = { [weak self] in self?.search() }
    }

    /// Showing and not on its way out.
    var isVisible: Bool { (panel?.isVisible ?? false) && closeTask == nil }
    private var closeTask: Task<Void, Never>?

    /// Opens the ring centred near `point`, in global AppKit coordinates.
    func show(at point: CGPoint, holding: Bool = false, dropping: Bool = false) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let screen else { return }
        services.orbDock.hide()
        RingIconCache.shared.retryMissing()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        model.set = services.preferences.ringConfig.set(forFrontApp: front)
        model.agentChoices = RingAgentChoices.choices(for: agentEntries())
        let state = services.formUnderPointer()
        model.formChoices = RingFormChoices.choices(current: state.form, systemIsland: state.systemIsland)
        model.running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        model.frontmost = front
        listFolders()
        model.hover = .none
        model.expanded = nil
        model.picked = nil
        model.query = ""
        model.results = []
        model.selectedResult = 0
        pressPoint = point
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
        let side = Self.side
        let frame = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        model.centre = CGPoint(x: side / 2, y: side / 2)

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

    /// A file drag ended; give a drop on the ring time to land, then put the ring away.
    func dragEnded() {
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
        model.visible = false
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            panel.orderOut(nil)
            self.model.dropping = false
            self.closeTask = nil
        }
    }

    func toggle(at point: CGPoint) {
        if isVisible { hide() } else { show(at: point) }
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
        let outcome = RingFlick.release(
            after: Date.now.timeIntervalSince(openedAt), from: pressPoint, to: point, centre: centre,
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
        hovered(hit(atGlobal: point), distance: hypot(point.x - frame.midX, point.y - frame.midY))
    }

    func hovered(_ hit: RingHit, distance: CGFloat) {
        model.hover = hit
        model.expanded = RingInteraction.expanded(
            current: model.expanded, hit: hit, distance: distance,
            hasSubItems: { [model] in !model.subItems(of: $0).isEmpty })
    }

    /// Runs what was picked; files come from a drop.
    func pick(_ hit: RingHit, files: [URL]) {
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
            point, centre: centre, slots: model.set.slots.count, expanded: model.expanded,
            subItems: model.expandedItems.count)
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
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode, characters: characters, modified: modified) ?? false
            }
            return handled ? nil : event
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
        case .pickSlot(let index):
            guard index < model.set.slots.count else { return true }
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
        keyMonitor = nil
        clickMonitor = nil
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
            onDragOut: { [weak self] in self?.draggingOut() })
        panel.contentView = NSHostingView(rootView: view)
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
