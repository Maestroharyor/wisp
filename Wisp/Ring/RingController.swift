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
    var hover: RingHit = .none
    var expanded: Int?
    /// Files being dragged over the ring; segments that can't take them dim.
    var dropping = false
    /// The ring's centre, in the panel's own coordinates (y down).
    var centre: CGPoint = .zero

    /// The sub-ring entries of a segment: agent sessions for Agents, else its group.
    func subItems(of index: Int) -> [RingChoice] {
        guard set.slots.indices.contains(index) else { return [] }
        let slot = set.slots[index]
        if slot.action.kind == .agents { return agentChoices }
        return slot.group.enumerated().map { offset, action in
            RingChoice(id: "action:\(offset)", title: action.title, symbol: action.symbol)
        }
    }

    var expandedItems: [RingChoice] { expanded.map(subItems) ?? [] }
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
    /// Opened by holding a mouse button; letting go picks.
    private var holding = false

    private static let side = (RingGeometry.subRadius + RingGeometry.subStep + RingGeometry.margin) * 2

    init(services: AppServices) {
        self.services = services
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Opens the ring centred near `point`, in global AppKit coordinates.
    func show(at point: CGPoint, holding: Bool = false, dropping: Bool = false) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let screen else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        model.set = services.preferences.ringConfig.set(forFrontApp: front)
        model.agentChoices = RingAgentChoices.choices(for: agentEntries())
        model.hover = .none
        model.expanded = nil
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
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
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

    func hide() {
        dropEndTask?.cancel()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        stopMonitors()
        holding = false
        model.dropping = false
    }

    func toggle(at point: CGPoint) {
        if isVisible { hide() } else { show(at: point) }
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
        guard isVisible else { return }
        hovered(hit(atGlobal: point))
    }

    func hovered(_ hit: RingHit) {
        model.hover = hit
        switch hit {
        case .slot(let index):
            model.expanded = model.subItems(of: index).isEmpty ? nil : index
        case .centre:
            model.expanded = nil
        case .sub, .none:
            break
        }
    }

    /// Runs what was picked; files come from a drop.
    func pick(_ hit: RingHit, files: [URL]) {
        switch hit {
        case .centre:
            hide()
            // Files dropped on the middle go to the tray, like dropping them on the notch.
            if files.isEmpty { services.openShelf(.home) } else { services.tray.add(files) }
        case .slot(let index):
            guard model.set.slots.indices.contains(index) else { return }
            let slot = model.set.slots[index]
            // Agents has nothing to run itself; a click opens its sessions instead.
            if slot.action.kind == .agents, files.isEmpty, !model.agentChoices.isEmpty, model.expanded != index {
                model.expanded = index
                return
            }
            hide()
            run(slot.action, files: files)
        case .sub(let item):
            guard let index = model.expanded, model.set.slots.indices.contains(index) else { return }
            let slot = model.set.slots[index]
            hide()
            if slot.action.kind == .agents {
                runAgentChoice(model.agentChoices[safe: item])
            } else if let action = slot.group[safe: item] {
                run(action, files: files)
            }
        case .none:
            hide()
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
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            onHover: { [weak self] hit in self?.hovered(hit) },
            onPick: { [weak self] hit, files in self?.pick(hit, files: files) })
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
