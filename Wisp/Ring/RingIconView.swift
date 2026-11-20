import AppKit
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

@MainActor
final class RingIconCache {
    static let shared = RingIconCache()

    private let cache = NSCache<NSString, NSImage>()
    /// Icons that couldn't be found, so a missing app or an unreachable folder isn't looked up
    /// again on every redraw.
    private var missing: Set<String> = []

    init() {
        cache.countLimit = 128
    }

    func image(for icon: RingIcon) -> NSImage? {
        let key: String
        switch icon {
        case .symbol: return nil
        case .app(let id): key = "app:" + id
        case .file(let path): key = "file:" + path
        }
        if let image = cache.object(forKey: key as NSString) { return image }
        if missing.contains(key) { return nil }
        let image: NSImage?
        switch icon {
        case .symbol: image = nil
        case .app(let id): image = AppIcon.app(id)
        case .file(let path):
            image = FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
        }
        if let image { cache.setObject(image, forKey: key as NSString) } else { missing.insert(key) }
        return image
    }

    /// Apps installed or folders reconnected since are looked for again.
    func retryMissing() {
        missing.removeAll()
    }
}
