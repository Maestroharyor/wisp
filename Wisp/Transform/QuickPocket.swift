import AppKit
import SwiftUI
import WispCore

/// A 2×2 grid of drop targets that appears right where you are when you shake a file
/// mid-drag (or as soon as a drag starts, if set), so you don't have to reach the notch.
@MainActor
final class QuickPocket {
    private let services: AppServices
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private let size = CGSize(width: 236, height: 236)

    init(services: AppServices) {
        self.services = services
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(at point: CGPoint) {
        hideTask?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel
        guard !panel.isVisible else { return }
        // Up and to the right of the pointer, kept on screen.
        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? .zero
        var origin = CGPoint(x: point.x + 24, y: point.y - size.height / 2)
        if origin.x + size.width > screen.maxX { origin.x = point.x - size.width - 24 }
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    /// The drag ended: give the drop handler a moment, then fade out.
    func dragEnded() {
        guard isVisible else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PocketView(services: services))
        return panel
    }
}

private struct PocketView: View {
    let services: AppServices

    var body: some View {
        let tray = services.tray
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                DropTile(symbol: "tray.and.arrow.down.fill", title: "Drop") { tray.add($0) }
                DropTile(symbol: "wand.and.stars", title: "Transform") { services.openTransform($0) }
            }
            GridRow {
                DropTile(symbol: "doc.zipper", title: "Zip") { tray.zip($0) }
                DropTile(symbol: "airplayaudio", title: "AirDrop") { tray.airDrop($0) }
            }
        }
        .padding(10)
        .frame(width: 236, height: 236)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.1)))
        )
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
