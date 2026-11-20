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
    /// The windows of each running app segment, by segment, when it has more than one.
    var windowChoices: [Int: [RingChoice]] = [:]
    /// Apps running when the ring opened, for the dots under app segments.
    var running: Set<String> = []
    var frontmost: String?
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
    /// Counts window listings, so a late answer from an earlier opening is dropped.
    private var windowListings = 0
    /// Opened by holding a mouse button; letting go picks.
    private var holding = false

    private static let side = (RingGeometry.subOuter + RingGeometry.margin * 2) * 2

    init(services: AppServices) {
        self.services = services
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
        listWindows()
        model.hover = .none
        model.expanded = nil
        model.picked = nil
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
        switch RingGesture.release(after: Date.now.timeIntervalSince(openedAt), on: hit(atGlobal: point)) {
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
        let windowChoices = model.windowChoices
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

    /// Lists the windows of each running app on the ring, through Accessibility. Nothing is
    /// asked for when Accessibility isn't granted; the segments just have no window sub-ring.
    private func listWindows() {
        model.windowChoices = [:]
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
                guard let self, self.windowListings == listing, self.model.expanded != index else { return }
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
            let handled = MainActor.assumeIsolated { self?.handleKey(keyCode) ?? false }
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

    /// Esc closes the ring; 1 to 8 pick a segment.
    private func handleKey(_ keyCode: UInt16) -> Bool {
        guard isVisible else { return false }
        if keyCode == KeyCodes.escape {
            hide()
            return true
        }
        guard let digit = KeyCodes.digit(forKeyCode: keyCode), digit >= 1, digit <= model.set.slots.count else {
            return false
        }
        pick(.slot(digit - 1), files: [])
        return true
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
