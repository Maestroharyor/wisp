import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WispCore

@MainActor
@Observable
final class OrbDockModel {
    var apps: [RingAction] = []
    var running: Set<String> = []
    var frontmost: String?
    var visible = false
}

/// The orb as a dock: hovering it shows the ring's apps in a row beside it. Clicking one opens
/// it or brings it forward, and files dropped on one open with it. The row stays while the
/// pointer is on it, so it can be reached from the orb.
@MainActor
final class OrbDockController {
    private let services: AppServices
    private let model = OrbDockModel()
    private var panel: NSPanel?
    /// The orb peeking on each display, in global coordinates.
    private var peeking: [String: CGRect] = [:]
    private var shownFor: CGRect?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// Takes the panel away once it has faded; never cancelled by the orb peeking again, so a
    /// hidden dock can't be left on screen.
    private var orderOutTask: Task<Void, Never>?
    /// An orb found to have no apps to show, so it isn't looked up again on every redraw.
    private var emptyFor: CGRect?
    private var monitors: [Any] = []

    /// How long the orb must peek before the row shows, so passing over it doesn't flash it.
    private static let showAfter = Duration.milliseconds(120)
    /// Time to cross from the orb to the row before it goes.
    private static let hideAfter = Duration.milliseconds(350)

    init(services: AppServices) {
        self.services = services
    }

    /// An orb started or stopped peeking with nothing else to show.
    func orb(on display: String, peekingAt rect: CGRect?) {
        peeking[display] = rect
        // Leaving the orb is a fresh start: the front app or the ring may have changed.
        if rect == nil { emptyFor = nil }
        guard services.preferences.orbDock, !services.ring.isVisible, let orb = peeking.values.first else {
            showTask?.cancel()
            showTask = nil
            if shownFor != nil { scheduleHide() }
            return
        }
        hideTask?.cancel()
        hideTask = nil
        guard orb != shownFor, orb != emptyFor, showTask == nil else { return }
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showAfter)
            guard !Task.isCancelled, let self else { return }
            self.showTask = nil
            // Where the orb is now: it may have moved while this waited.
            guard let current = self.peeking.values.first else { return }
            self.show(beside: current)
        }
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        hideTask?.cancel()
        hideTask = nil
        stopMonitors()
        shownFor = nil
        model.visible = false
        guard let panel, panel.isVisible, orderOutTask == nil else { return }
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            self?.orderOutTask = nil
            // Shown again meanwhile: leave it.
            guard self?.shownFor == nil else { return }
            panel.orderOut(nil)
        }
    }

    /// The apps the dock shows, from the source chosen in Settings › Ring.
    static func apps(preferences: Preferences, front: String?) -> [RingAction] {
        let own = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id)
        }
        return RingDock.apps(
            source: preferences.orbDockSource,
            ring: RingController.shownSet(preferences: preferences, front: front).set,
            running: running, chosen: preferences.orbDockApps, names: AppNames.names(for: preferences.orbDockApps))
    }

    private func show(beside orb: CGRect) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let apps = Self.apps(preferences: services.preferences, front: front)
        let screen = NSScreen.screens.first { $0.frame.intersects(orb) } ?? NSScreen.main
        guard services.preferences.orbDock, !services.ring.isVisible, !apps.isEmpty, let screen else {
            if apps.isEmpty { emptyFor = orb }
            hide()
            return
        }
        emptyFor = nil
        model.apps = apps
        model.running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        model.frontmost = front

        let panel = panel ?? makePanel()
        self.panel = panel
        let frame = OrbDockGeometry.frame(orb: orb, count: apps.count, in: screen.visibleFrame)
        hideTask?.cancel()
        hideTask = nil
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        shownFor = orb
        Task { @MainActor [model] in model.visible = true }
        startMonitors()
    }

    /// Hides once the pointer has been off both the orb and the row for a moment.
    private func scheduleHide() {
        guard hideTask == nil else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideAfter)
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            if self.pointerIsNear() { return }
            self.hide()
        }
    }

    private func pointerIsNear() -> Bool {
        let mouse = NSEvent.mouseLocation
        if let frame = panel?.frame, frame.insetBy(dx: -6, dy: -6).contains(mouse) { return true }
        return peeking.values.contains { $0.insetBy(dx: -6, dy: -6).contains(mouse) }
    }

    private func pointerMoved() {
        guard shownFor != nil else { return }
        if pointerIsNear() {
            hideTask?.cancel()
            hideTask = nil
        } else {
            scheduleHide()
        }
    }

    private func picked(_ action: RingAction, files: [URL]) {
        hide()
        RingActionRunner.run(action, files: files, services: services)
    }

    private func startMonitors() {
        guard monitors.isEmpty else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    private func stopMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(
            rootView: OrbDockView(
                model: model, onPick: { [weak self] action, files in self?.picked(action, files: files) }))
        return panel
    }
}

/// The ring's apps in a frosted row, drawn as the ring draws them: the hovered one lifts with a
/// halo and its name shows in a pill above it.
private struct OrbDockView: View {
    let model: OrbDockModel
    let onPick: @MainActor (RingAction, [URL]) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let hovered, model.apps.indices.contains(hovered) {
                    Text(model.apps[hovered].title)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .wispSurface(Capsule(), role: .card)
                        .fixedSize()
                        .offset(x: labelOffset(for: hovered))
                        .transition(.opacity)
                        .id(hovered)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OrbDockGeometry.labelRoom)
            HStack(spacing: OrbDockGeometry.spacing) {
                ForEach(Array(model.apps.enumerated()), id: \.offset) { index, app in
                    icon(app, index: index)
                }
            }
            .padding(OrbDockGeometry.padding)
            .background(Capsule().fill(Color.wispViolet.opacity(0.06)))
            .wispSurface(Capsule())
            .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        }
        .scaleEffect(model.visible || reduceMotion ? 1 : 0.85, anchor: .bottom)
        .opacity(model.visible ? 1 : 0)
        .animation(
            model.visible ? .wispPopover : .wispDismiss, value: model.visible
        )
        .animation(reduceMotion ? nil : .wispControl, value: hovered)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Centres the name over its icon.
    private func labelOffset(for index: Int) -> CGFloat {
        let count = CGFloat(model.apps.count)
        let step = OrbDockGeometry.icon + OrbDockGeometry.spacing
        return (CGFloat(index) - (count - 1) / 2) * step
    }

    private func icon(_ app: RingAction, index: Int) -> some View {
        let dot = RingRunState.dot(for: app, running: model.running, frontmost: model.frontmost)
        let side = OrbDockGeometry.icon
        let lit = hovered == index
        return Button {
            onPick(app, [])
        } label: {
            ZStack(alignment: .bottom) {
                RingTileIcon(icon: app.icon, tileHex: app.tileHex, side: side)
                    .scaleEffect(lit && !reduceMotion ? 1.15 : 1, anchor: .bottom)
                    .shadow(color: lit ? Color.wispViolet.opacity(0.45) : .clear, radius: 10)
                if dot != .none {
                    Circle().fill(dot == .frontmost ? Color.wispViolet : Color.primary.opacity(0.55))
                        .frame(width: 4, height: 4).offset(y: 6)
                }
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.title)
        .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            FileDrop.handler { urls in onPick(app, urls) }(providers)
        }
    }
}

/// Apps' names as Finder shows them, for bundle ids saved without one.
@MainActor
enum AppNames {
    static func names(for ids: [String]) -> [String: String] {
        var names: [String: String] = [:]
        for id in ids {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            names[id] = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        }
        return names
    }
}
