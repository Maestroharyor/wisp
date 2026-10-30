import Foundation

/// Files parked in the tray, newest first, with a selection.
public struct TrayList: Sendable, Equatable {
    public private(set) var urls: [URL] = []
    public private(set) var selected: Set<URL> = []

    public init(urls: [URL] = []) {
        add(urls)
    }

    /// Adds files at the front, skipping ones already in the tray.
    public mutating func add(_ newURLs: [URL]) {
        let fresh = newURLs.reduce(into: [URL]()) { result, url in
            if !urls.contains(url), !result.contains(url) { result.append(url) }
        }
        urls.insert(contentsOf: fresh, at: 0)
    }

    public mutating func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        selected.remove(url)
    }

    public mutating func removeSelected() {
        urls.removeAll(where: selected.contains)
        selected.removeAll()
    }

    public mutating func removeAll() {
        urls.removeAll()
        selected.removeAll()
    }

    public mutating func toggleSelection(_ url: URL) {
        guard urls.contains(url) else { return }
        if selected.remove(url) == nil { selected.insert(url) }
    }

    public mutating func selectAll() {
        selected = Set(urls)
    }

    public mutating func toggleSelectAll() {
        if !urls.isEmpty, selected.count == urls.count { selected.removeAll() } else { selectAll() }
    }

    /// What an action applies to: the selection if there is one, otherwise everything.
    public var actionTargets: [URL] {
        selected.isEmpty ? urls : urls.filter(selected.contains)
    }

    /// Drops files that no longer exist.
    public mutating func prune(keeping exists: (URL) -> Bool) {
        urls.removeAll { !exists($0) }
        selected = selected.filter(exists)
    }
}

/// Picks a free name for a zip archive next to the originals.
public enum ArchiveNaming {
    public static func name(for urls: [URL], existing: Set<String>) -> String {
        let base = urls.count == 1 ? (urls.first?.deletingPathExtension().lastPathComponent ?? "Archive") : "Archive"
        var candidate = "\(base).zip"
        var index = 2
        while existing.contains(candidate) {
            candidate = "\(base) \(index).zip"
            index += 1
        }
        return candidate
    }

    /// Names for files gathered into one folder before zipping. Files with the same name
    /// from different folders get " 2", " 3" before the extension instead of clashing.
    public static func stagedNames(for urls: [URL]) -> [String] {
        var used: Set<String> = []
        return urls.map { url in
            let name = url.lastPathComponent
            let ext = url.pathExtension
            let stem = url.deletingPathExtension().lastPathComponent
            var candidate = name
            var index = 2
            while used.contains(candidate) {
                candidate = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
                index += 1
            }
            used.insert(candidate)
            return candidate
        }
    }
}
