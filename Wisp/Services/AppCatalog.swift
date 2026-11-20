import AppKit
import WispCore

/// The apps on this Mac, for typing on the ring. Listed off the main thread from the usual
/// Applications folders when the ring opens, at most every few minutes; only names, bundle
/// identifiers and paths are kept, and only in memory.
@MainActor
final class AppCatalog {
    private(set) var apps: [InstalledApp] = []
    /// Runs when a new list arrives, so a search typed meanwhile can be run again.
    var onChange: () -> Void = {}

    private var loadedAt: Date?
    private var loading = false
    private static let freshFor: TimeInterval = 300

    func refreshIfStale() {
        if loading { return }
        if let loadedAt, Date.now.timeIntervalSince(loadedAt) < Self.freshFor { return }
        loading = true
        Task { [weak self] in
            let apps = await Self.scan()
            guard let self else { return }
            self.apps = apps
            self.loadedAt = .now
            self.loading = false
            self.onChange()
        }
    }

    private nonisolated static func scan() async -> [InstalledApp] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: list())
            }
        }
    }

    private nonisolated static func list() -> [InstalledApp] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.path
        let folders = [
            "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
            home + "/Applications",
        ]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for folder in folders {
            let names = (try? manager.contentsOfDirectory(atPath: folder)) ?? []
            for name in names.sorted() where name.hasSuffix(".app") {
                let path = (folder as NSString).appendingPathComponent(name)
                guard let id = Bundle(path: path)?.bundleIdentifier, seen.insert(id).inserted else { continue }
                // Finder usually hides ".app" already; a dot in the name itself ("draw.io") stays.
                let shown = manager.displayName(atPath: path)
                let display = shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
                apps.append(InstalledApp(name: display, bundleID: id, path: path))
            }
        }
        return apps
    }
}
