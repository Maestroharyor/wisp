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
    /// Reads the text in an image item and copies it (the card menu's Copy text).
    @ObservationIgnored var copyText: (ClipItem) -> Void = { _ in }

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
        model.copyText = { [weak services] item in services?.textCapture.copyText(from: item) }
    }

    /// Fading out; a show() meanwhile cancels the pending orderOut.
    private var hiding = false

    /// False while fading out, so the shortcut pressed again during the fade shows it.
    var isVisible: Bool { (panel?.isVisible ?? false) && !hiding }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        hiding = false
        model.query = ""
        model.selectedID = model.items.first?.id
        services.aiActions.refresh()

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
        guard let panel, panel.isVisible, !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hiding else { return }
                self.hiding = false
                panel.orderOut(nil)
            }
        }
    }

    /// Copies the item, closes the panel and sends ⌘V to the app in front.
    func paste(_ item: ClipItem) {
        services.clipboard.copy(item)
        hide()
        guard AccessibilityPermission.isTrusted else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            PasteShortcut.send()
        }
    }

    /// Closes the panel, so the card under the notch shows, and runs the task on the item.
    func runAI(_ task: AITask, on item: ClipItem) {
        hide()
        services.aiActions.run(task, on: item)
    }

    private func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel(contentRect: CGRect(origin: .zero, size: size))
        let view = ClipboardView(
            model: model,
            ai: services.aiActions,
            paste: { [weak self] in self?.paste($0) },
            runAI: { [weak self] in self?.runAI($0, on: $1) },
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
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = modifiers.contains(.command)
            let commandOnly = modifiers == .command
            let handled = MainActor.assumeIsolated {
                self?.handleKey(keyCode, command: command, commandOnly: commandOnly) ?? false
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Key codes of 1 to 8 on the number row.
    private static let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28]

    private func handleKey(_ keyCode: UInt16, command: Bool, commandOnly: Bool) -> Bool {
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
        case let key where commandOnly && Self.digitKeys.contains(key):  // ⌘1 to ⌘8: AI tasks
            let actions = services.aiActions
            guard actions.isEnabled, let index = Self.digitKeys.firstIndex(of: key),
                actions.tasks.indices.contains(index), let item = model.selectedItem, AIClipboardText.offers(item)
            else { return false }
            // Not ready: say why and keep the panel open.
            guard actions.isReady else {
                actions.showStatus()
                return true
            }
            runAI(actions.tasks[index], on: item)
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
