import AppKit
import SwiftUI
import WispCore

/// A small floating player that stays on top of other windows: artwork, controls,
/// progress and the current lyric line. Drag it anywhere; it reopens where it was left.
@MainActor
final class MiniPlayerController {
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private let services: AppServices

    private static let size = CGSize(width: 320, height: 118)

    init(services: AppServices) {
        self.services = services
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(savedOrigin() ?? defaultOrigin())
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(
            rootView: MiniPlayerView(
                monitor: services.nowPlaying, lyrics: services.lyrics,
                close: { [weak self] in self?.hide() }))
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let origin = self?.panel?.frame.origin else { return }
                self?.services.preferences.miniPlayerOrigin = "\(Int(origin.x)),\(Int(origin.y))"
            }
        }
        return panel
    }

    private func savedOrigin() -> CGPoint? {
        guard let parts = services.preferences.miniPlayerOrigin?.split(separator: ","), parts.count == 2,
            let x = Double(parts[0]), let y = Double(parts[1])
        else { return nil }
        let origin = CGPoint(x: x, y: y)
        // Forget a spot on a display that's no longer connected.
        let visible = NSScreen.screens.contains { $0.visibleFrame.contains(CGPoint(x: x + 20, y: y + 20)) }
        return visible ? origin : nil
    }

    private func defaultOrigin() -> CGPoint {
        let frame = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(x: frame.maxX - Self.size.width - 24, y: frame.minY + 24)
    }
}

private struct MiniPlayerView: View {
    let monitor: NowPlayingMonitor
    let lyrics: LyricsStore
    let close: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ArtworkView(image: monitor.artwork, size: 44, radius: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.info?.title ?? "Nothing playing").font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(monitor.info?.artist ?? "Play something").font(.system(size: 11))
                        .foregroundStyle(Color.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ShelfButton(symbol: "backward.fill", size: 11) { monitor.previous() }
                    ShelfButton(
                        symbol: monitor.info?.isPlaying == true ? "pause.fill" : "play.fill", size: 14
                    ) { monitor.togglePlayPause() }
                    ShelfButton(symbol: "forward.fill", size: 11) { monitor.next() }
                }
            }
            if let info = monitor.info {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ProgressBar(
                        value: info.duration > 0 ? monitor.position(at: context.date) / info.duration : 0,
                        tint: .accentColor, height: 4
                    ) { monitor.seek(to: $0 * info.duration) }
                }
                LyricLines(monitor: monitor, lyrics: lyrics, size: 12, showsNext: false)
            } else {
                Text("Music from any app or browser shows here, with lyrics as it plays.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 320, height: 118, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1))
                )
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                ShelfButton(symbol: "xmark", size: 8, action: close).offset(x: 6, y: -6)
            }
        }
        .onHover { hovering = $0 }
        .foregroundStyle(.white)
    }
}
