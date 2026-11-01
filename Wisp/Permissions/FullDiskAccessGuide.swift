import AppKit
import SwiftUI

/// Full Disk Access has no prompt, and macOS never lists an app there by itself: it has to
/// be dragged in or added with +. This small panel sits beside System Settings with Wisp's
/// icon to drag, and closes itself once access is on.
@MainActor
final class FullDiskAccessGuide {
    static let shared = FullDiskAccessGuide()

    private var panel: NSPanel?
    private var watcher: Task<Void, Never>?
    private let state = GuideState()
    private static let size = CGSize(width: 300, height: 176)

    func show() {
        Permission.fullDiskAccess.openSettings()
        let panel = panel ?? makePanel()
        self.panel = panel
        state.granted = false
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(
                CGPoint(x: screen.maxX - Self.size.width - 24, y: screen.midY - Self.size.height / 2))
        }
        panel.orderFrontRegardless()
        watch()
    }

    func close() {
        watcher?.cancel()
        watcher = nil
        panel?.orderOut(nil)
    }

    /// Checks once a second for up to ten minutes; access works as soon as the switch is on.
    private func watch() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            for _ in 0..<600 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard Permission.hasFullDiskAccess else { continue }
                self?.state.granted = true
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.close()
                return
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: GuideView(state: state, close: { [weak self] in self?.close() }))
        return panel
    }
}

@MainActor
@Observable
private final class GuideState {
    var granted = false
}

private struct GuideView: View {
    let state: GuideState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.granted {
                Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.wispGreen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable()
                        .frame(width: 52, height: 52)
                        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                        .help("Drag into the Full Disk Access list")
                        .accessibilityLabel("Wisp app, drag into the list")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drag Wisp into the Full Disk Access list, then switch it on.")
                            .font(.system(size: 13, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Or click + under the list and choose Wisp.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    Spacer()
                    Button("Close", action: close).keyboardShortcut(.cancelAction)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300, height: 176)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
    }
}
