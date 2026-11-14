import AppKit
import Observation
import QuickLookThumbnailing
import WispCore

/// Files parked in the tray, with thumbnails and file actions. The tray keeps
/// references only; files stay where they are.
@MainActor
@Observable
final class TrayStore {
    private(set) var list = TrayList()
    private(set) var thumbnails: [URL: NSImage] = [:]
    /// File sizes, read once when a file arrives. Folders have none.
    private(set) var sizes: [URL: Int64] = [:]
    /// Which files are folders, read with their sizes.
    private(set) var folders: Set<URL> = []

    @ObservationIgnored var onAdd: (Int) -> Void = { _ in }
    @ObservationIgnored var onNotice: (String, String) -> Void = { _, _ in }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "trayPaths"
    @ObservationIgnored private var lastPrune = Date.distantPast
    @ObservationIgnored private var pruning = false
    /// The last add still checking its files; later adds wait for it, so the tray keeps the
    /// order files were added in.
    @ObservationIgnored private var adding: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: key) ?? []
        list = TrayList(urls: paths.map { URL(fileURLWithPath: $0) }.reversed())
        list.urls.forEach(loadThumbnail)
        pruneMissing()
    }

    var count: Int { list.urls.count }

    /// "2 files · 3.4 MB", or what is selected.
    var header: String {
        TraySummary.header(
            sizes: list.urls.compactMap { sizes[$0] },
            selectedSizes: list.urls.filter(list.selected.contains).compactMap { sizes[$0] },
            count: count)
    }

    /// "PNG · 1.2 MB", or "Folder".
    func detail(for url: URL) -> String {
        if folders.contains(url) { return "Folder" }
        return TraySummary.detail(pathExtension: url.pathExtension, size: sizes[url])
    }

    /// Checks the files exist off the main thread (a network volume can take a while), then
    /// adds the ones that do.
    func add(_ urls: [URL]) {
        let previous = adding
        adding = Task { [weak self] in
            let existing = await Task.detached(priority: .userInitiated) { urls.filter(Self.exists) }.value
            await previous?.value
            self?.insert(existing)
        }
    }

    private func insert(_ existing: [URL]) {
        let before = count
        list.add(existing)
        existing.forEach(loadThumbnail)
        save()
        if count > before { onAdd(count) }
    }

    /// Drops cards for files that were moved or deleted since they were added. At most once
    /// a minute, and the files are checked off the main thread, since a slow network volume
    /// would otherwise hitch the shelf.
    func pruneMissing() {
        guard !pruning, Date.now.timeIntervalSince(lastPrune) > 60 else { return }
        lastPrune = .now
        pruning = true
        let urls = list.urls
        Task { [weak self] in
            let missing = await Task.detached(priority: .utility) { Set(urls.filter { !Self.isKept($0) }) }.value
            guard let self else { return }
            self.pruning = false
            guard !missing.isEmpty else { return }
            self.list.prune { !missing.contains($0) }
            for url in missing {
                self.thumbnails[url] = nil
                self.sizes[url] = nil
                self.folders.remove(url)
            }
            self.save()
        }
    }

    func remove(_ url: URL) {
        list.remove(url)
        thumbnails[url] = nil
        sizes[url] = nil
        folders.remove(url)
        save()
    }

    func removeSelectedOrAll() {
        if list.selected.isEmpty { list.removeAll() } else { list.removeSelected() }
        thumbnails = thumbnails.filter { list.urls.contains($0.key) }
        sizes = sizes.filter { list.urls.contains($0.key) }
        folders = folders.filter(list.urls.contains)
        save()
    }

    func toggleSelection(_ url: URL) { list.toggleSelection(url) }
    func toggleSelectAll() { list.toggleSelectAll() }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls)
        else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    /// Zips the files next to the first one, then adds the archive to the tray.
    func zip(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let folder = first.deletingLastPathComponent()
        let names = ArchiveNaming.stagedNames(for: urls)
        Task { [weak self] in
            let output = await Self.archive(urls, names: names, in: folder)
            if let output { self?.add([output]) }
            let ok = output != nil
            self?.onNotice(ok ? "doc.zipper" : "xmark.circle.fill", ok ? "Zipped" : "Zip failed")
        }
    }

    /// Off the main thread: listing the folder for a free name, and copying gigabytes into the
    /// staging folder, both take a while. ditto archives one source, so several files are cloned
    /// into a temporary folder first (cheap on APFS), which is removed afterwards. Returns the
    /// archive, or nil when it failed.
    private nonisolated static func archive(_ urls: [URL], names: [String], in parent: URL) async -> URL? {
        let files = FileManager.default
        let existing = Set((try? files.contentsOfDirectory(atPath: parent.path)) ?? [])
        let output = parent.appendingPathComponent(ArchiveNaming.name(for: urls, existing: existing))
        var arguments = ["-c", "-k", "--sequesterRsrc"]
        var staging: URL?
        if urls.count == 1, let only = urls.first {
            arguments += ["--keepParent", only.path, output.path]
        } else {
            let folder = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            staging = folder
            do {
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
                for (url, name) in Swift.zip(urls, names) {
                    try files.copyItem(at: url, to: folder.appendingPathComponent(name))
                }
            } catch {
                try? files.removeItem(at: folder)
                return nil
            }
            arguments += [folder.path, output.path]
        }
        defer { if let staging { try? files.removeItem(at: staging) } }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let ok = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
        return ok ? output : nil
    }

    private func save() {
        defaults.set(list.urls.reversed().map(\.path), forKey: key)
    }

    private func loadThumbnail(_ url: URL) {
        guard thumbnails[url] == nil else { return }
        thumbnails[url] = NSWorkspace.shared.icon(forFile: url.path)
        Task { [weak self] in
            let facts = await Task.detached(priority: .utility) { Self.facts(of: url) }.value
            guard let self, self.list.urls.contains(url) else { return }
            if let size = facts.size { self.sizes[url] = size }
            if facts.isFolder { self.folders.insert(url) }
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 168, height: 168), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            Task { @MainActor in
                guard self?.list.urls.contains(url) == true else { return }
                self?.thumbnails[url] = NSImage(cgImage: cgImage, size: size)
            }
        }
    }

    private struct FileFacts: Sendable {
        var size: Int64?
        var isFolder: Bool
    }

    private nonisolated static func facts(of url: URL) -> FileFacts {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        return FileFacts(size: values?.fileSize.map(Int64.init), isFolder: values?.isDirectory == true)
    }

    private nonisolated static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Cards for files on an ejected drive stay, so they come back when it does.
    private nonisolated static func isKept(_ url: URL) -> Bool {
        TrayList.keeps(url) { FileManager.default.fileExists(atPath: $0) }
    }
}
