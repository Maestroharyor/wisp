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

    @ObservationIgnored var onAdd: (Int) -> Void = { _ in }
    @ObservationIgnored var onNotice: (String, String) -> Void = { _, _ in }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "trayPaths"
    @ObservationIgnored private var lastPrune = Date.distantPast

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: key) ?? []
        list = TrayList(urls: paths.map { URL(fileURLWithPath: $0) }.reversed())
        list.prune(keeping: Self.exists)
        list.urls.forEach(loadThumbnail)
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
        if sizes[url] == nil, Self.isFolder(url) { return "Folder" }
        return TraySummary.detail(pathExtension: url.pathExtension, size: sizes[url])
    }

    func add(_ urls: [URL]) {
        let before = count
        let existing = urls.filter(Self.exists)
        list.add(existing)
        existing.forEach(loadThumbnail)
        save()
        if count > before { onAdd(count) }
    }

    /// Drops cards for files that were moved or deleted since they were added. At most once
    /// a minute, since checking files on a slow network volume would hitch the shelf.
    func pruneMissing() {
        guard Date.now.timeIntervalSince(lastPrune) > 60 else { return }
        lastPrune = .now
        let before = list.urls
        list.prune(keeping: Self.exists)
        guard list.urls != before else { return }
        for url in before where !list.urls.contains(url) {
            thumbnails[url] = nil
            sizes[url] = nil
        }
        save()
    }

    func remove(_ url: URL) {
        list.remove(url)
        thumbnails[url] = nil
        sizes[url] = nil
        save()
    }

    func removeSelectedOrAll() {
        if list.selected.isEmpty { list.removeAll() } else { list.removeSelected() }
        thumbnails = thumbnails.filter { list.urls.contains($0.key) }
        sizes = sizes.filter { list.urls.contains($0.key) }
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
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let output = folder.appendingPathComponent(ArchiveNaming.name(for: urls, existing: existing))

        let names = ArchiveNaming.stagedNames(for: urls)
        Task { [weak self] in
            let ok = await Self.archive(urls, names: names, to: output)
            if ok { self?.add([output]) }
            self?.onNotice(ok ? "doc.zipper" : "xmark.circle.fill", ok ? "Zipped" : "Zip failed")
        }
    }

    /// Off the main thread: copying gigabytes into the staging folder takes a while.
    /// ditto archives one source, so several files are cloned into a temporary folder first
    /// (cheap on APFS), which is removed afterwards.
    private nonisolated static func archive(_ urls: [URL], names: [String], to output: URL) async -> Bool {
        let files = FileManager.default
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
                return false
            }
            arguments += [folder.path, output.path]
        }
        defer { if let staging { try? files.removeItem(at: staging) } }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }

    private func save() {
        defaults.set(list.urls.reversed().map(\.path), forKey: key)
    }

    private func loadThumbnail(_ url: URL) {
        guard thumbnails[url] == nil else { return }
        thumbnails[url] = NSWorkspace.shared.icon(forFile: url.path)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { sizes[url] = Int64(size) }
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

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private nonisolated static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
