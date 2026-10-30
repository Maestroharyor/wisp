import AppKit
import Observation
import WispCore

/// The desktop picture's average colour, for the "match the wallpaper" glow. Read when
/// turned on, when Spaces or displays change, and every few minutes for dynamic
/// wallpapers. The picture is downsampled before averaging, off the main thread.
@MainActor
@Observable
final class WallpaperTint {
    private(set) var color: RGB?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var sampling: Task<Void, Never>?

    var isRunning: Bool { refreshTask != nil }

    func start() {
        guard refreshTask == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sample() }
                })
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            })
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        sampling?.cancel()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        color = nil
    }

    private func sample() {
        guard let screen = NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.main,
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return }
        sampling?.cancel()
        sampling = Task { [weak self] in
            let average = await Self.average(of: url)
            guard !Task.isCancelled, let average else { return }
            self?.color = average.liftedForGlow()
        }
    }

    private nonisolated static func average(of url: URL) async -> RGB? {
        // A thumbnail is plenty for an average and avoids decoding a 6K picture.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return ImageColor.average(of: NSImage(cgImage: thumbnail, size: .zero))
    }
}
