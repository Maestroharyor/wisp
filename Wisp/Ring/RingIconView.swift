import AppKit
import Observation
import SwiftUI
import WispCore

/// A ring icon: an SF Symbol, or an app's or file's own icon from a small cache, so opening
/// the ring doesn't ask Launch Services for every icon again.
struct RingIconView: View {
    let icon: RingIcon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size, weight: .semibold))
        case .app, .file:
            if let image = RingIconCache.shared.image(for: icon) {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: size * 1.7, height: size * 1.7)
            } else {
                Image(systemName: fallback).font(.system(size: size, weight: .semibold))
            }
        }
    }

    private var fallback: String {
        if case .file = icon { return "doc" }
        return "app.dashed"
    }
}

/// A ring icon at full size, as the ring and the orb's dock draw it: an app's or file's own
/// icon, or a built-in action's symbol on a coloured tile shaped like an app icon, so actions
/// and apps sit together as one row of icons.
struct RingTileIcon: View {
    let icon: RingIcon
    /// The tile colour for a symbol; apps and files ignore it.
    let tileHex: String
    let side: CGFloat

    var body: some View {
        switch icon {
        case .symbol(let name):
            symbolTile(name)
        case .app, .file:
            if let image = RingIconCache.shared.image(for: icon) {
                // App icons carry their own margin (about a tenth each side); drawn larger, they line
                // up with the tiles.
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: side * 1.24, height: side * 1.24)
                    .frame(width: side, height: side)
            } else {
                symbolTile(isFile ? "doc" : "app.dashed")
            }
        }
    }

    private var isFile: Bool {
        if case .file = icon { return true }
        return false
    }

    private func symbolTile(_ name: String) -> some View {
        let colour = Color(ringHex: tileHex)
        return RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [colour.opacity(0.82), colour], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: name).font(.system(size: side * 0.44, weight: .semibold)).foregroundStyle(.white)
            )
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.16), radius: side * 0.06, y: side * 0.03)
    }
}

extension Color {
    /// A colour from `#RRGGBB`; grey when the text isn't one.
    init(ringHex hex: String) {
        let rgb = ClipClassifier.rgb(fromHex: hex) ?? (red: 142, green: 142, blue: 147)
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

/// App and file icons, cached so opening the ring doesn't ask Launch Services for every icon
/// again. File icons load on a dispatch queue: a folder on a share that has gone away can block
/// for a long time, and the ring mustn't wait for it. Views redraw when one arrives.
@MainActor
@Observable
final class RingIconCache {
    static let shared = RingIconCache()

    /// Bumped when a file icon arrives, so views showing a placeholder look again.
    private(set) var arrivals = 0
    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()
    /// Icons that couldn't be found, and when, so a missing app or an unreachable folder isn't
    /// looked up on every redraw, but is tried again after a while.
    @ObservationIgnored private var missing: [String: Date] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    private static let retryAfter: TimeInterval = 60

    init() {
        cache.countLimit = 128
    }

    func image(for icon: RingIcon) -> NSImage? {
        switch icon {
        case .symbol: return nil
        case .app(let id):
            let key = "app:" + id
            if let image = cached(key) { return image }
            guard !isMissing(key) else { return nil }
            return store(AppIcon.app(id), for: key)
        case .file(let path):
            let key = "file:" + path
            _ = arrivals
            if let image = cached(key) { return image }
            guard !isMissing(key), !loading.contains(key) else { return nil }
            load(path, key: key)
            return nil
        }
    }

    /// Icons that weren't found a while ago are looked for again.
    func retryMissing(now: Date = .now) {
        missing = missing.filter { now.timeIntervalSince($0.value) < Self.retryAfter }
    }

    private func cached(_ key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    private func isMissing(_ key: String) -> Bool {
        guard let since = missing[key] else { return false }
        return Date.now.timeIntervalSince(since) < Self.retryAfter
    }

    private func store(_ image: NSImage?, for key: String) -> NSImage? {
        if let image {
            cache.setObject(image, forKey: key as NSString)
            missing[key] = nil
        } else {
            missing[key] = .now
        }
        return image
    }

    private func load(_ path: String, key: String) {
        loading.insert(key)
        Task { @MainActor in
            let icon = await withCheckedContinuation { (continuation: CheckedContinuation<LoadedIcon, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let image =
                        FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
                    continuation.resume(returning: LoadedIcon(image: image))
                }
            }
            loading.remove(key)
            _ = store(icon.image, for: key)
            arrivals += 1
        }
    }
}

/// A file icon handed from the queue that loaded it to the main actor. `@unchecked Sendable` is
/// safe: the image is made on that queue, never touched there again, and only read afterwards.
private struct LoadedIcon: @unchecked Sendable {
    let image: NSImage?
}
