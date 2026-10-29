import AppKit
import Observation
import SwiftUI
import WispCore

/// Selection and filters for the clipboard panel.
@MainActor
@Observable
final class ClipboardPanelModel {
    var kind: ClipKind?
    var query = ""
    var selectedID: UUID?

    let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    var items: [ClipItem] { store.history.filtered(kind: kind, query: query) }

    var selectedItem: ClipItem? {
        items.first { $0.id == selectedID } ?? items.first
    }

    func move(by offset: Int) {
        let items = items
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedItem?.id } ?? 0
        selectedID = items[min(max(index + offset, 0), items.count - 1)].id
    }
}

/// Floating panel along the bottom of the screen with the clipboard history.
/// Return pastes into the app that was in front; Esc closes.
@MainActor
final class ClipboardPanelController {
    private let services: AppServices
    private var panel: ClipboardPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private let model: ClipboardPanelModel

    private let size = CGSize(width: 900, height: 330)

    init(services: AppServices) {
        self.services = services
        model = ClipboardPanelModel(store: services.clipboard)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        model.query = ""
        model.selectedID = model.items.first?.id

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(
                CGRect(x: visible.midX - size.width / 2, y: visible.minY + 24, width: size.width, height: size.height),
                display: true)
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// Copies the item, closes the panel and sends ⌘V to the app in front.
    func paste(_ item: ClipItem) {
        services.clipboard.copy(item)
        hide()
        guard AccessibilityPermission.isTrusted else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            Self.sendPasteShortcut()
        }
    }

    private func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel(contentRect: CGRect(origin: .zero, size: size))
        let view = ClipboardView(
            model: model,
            paste: { [weak self] in self?.paste($0) },
            close: { [weak self] in self?.hide() }
        )
        panel.contentView = NSHostingView(rootView: view)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            // Context menus take key briefly; only close when focus has really left.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let panel = self.panel, !panel.isKeyWindow else { return }
                self.hide()
            }
        }
        return panel
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let command = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated { self?.handleKey(keyCode, command: command) ?? false }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleKey(_ keyCode: UInt16, command: Bool) -> Bool {
        guard isVisible else { return false }
        switch keyCode {
        case 53:  // Esc
            hide()
        case 123:  // Left
            model.move(by: -1)
        case 124:  // Right
            model.move(by: 1)
        case 36, 76:  // Return, Enter
            if let item = model.selectedItem { paste(item) }
        case 51 where command:  // ⌘Delete
            if let item = model.selectedItem {
                model.move(by: 1)
                services.clipboard.remove(item)
            }
        default:
            return false
        }
        return true
    }

    private static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

/// Key-capable panel that never activates Wisp, so the previous app stays in front.
final class ClipboardPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
