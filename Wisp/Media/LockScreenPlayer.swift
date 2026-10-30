import AppKit
import SwiftUI
import WispCore

/// While the screen is locked and music plays, shows a player above the lock screen.
/// Public APIs only: the lock and unlock distributed notifications and the shielding
/// window level. If macOS keeps third-party windows off the lock screen, it simply
/// doesn't appear.
@MainActor
final class LockScreenPlayer {
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers.append(
            center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.locked() }
            })
        observers.append(
            center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
            })
    }

    func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers = []
        panel?.orderOut(nil)
    }

    private func locked() {
        guard services.preferences.lockScreenPlayer, services.nowPlaying.info != nil,
            let screen = NSScreen.main
        else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        let size = panel.frame.size
        let frame = screen.frame
        panel.setFrameOrigin(CGPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.16))
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let size = CGSize(width: 360, height: 96)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: LockScreenPlayerView(monitor: services.nowPlaying))
        return panel
    }
}

private struct LockScreenPlayerView: View {
    let monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: monitor.artwork, size: 60, radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.info?.title ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(monitor.info?.artist ?? "").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            ShelfButton(symbol: "backward.fill", size: 13) { monitor.previous() }
            ShelfButton(symbol: monitor.info?.isPlaying == true ? "pause.fill" : "play.fill", size: 17) {
                monitor.togglePlayPause()
            }
            ShelfButton(symbol: "forward.fill", size: 13) { monitor.next() }
        }
        .padding(.horizontal, 18)
        .frame(width: 360, height: 96)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black.opacity(0.7)))
        .foregroundStyle(.white)
    }
}
