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
        list.add(urls.filter(Self.exists))
        urls.forEach(loadThumbnail)
        save()
        if count > before { onAdd(count) }
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        if urls.count == 1 {
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, output.path]
        } else {
            // ditto archives one source; stage the files in a temporary folder first.
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                for url in urls {
                    try FileManager.default.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent))
                }
            } catch {
                onNotice("xmark.circle.fill", "Zip failed")
                return
            }
            process.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, output.path]
        }
        process.terminationHandler = { [weak self] finished in
            let ok = finished.terminationStatus == 0
            Task { @MainActor in
                if ok { self?.add([output]) }
                self?.onNotice(ok ? "doc.zipper" : "xmark.circle.fill", ok ? "Zipped" : "Zip failed")
            }
        }
        do {
            try process.run()
        } catch {
            onNotice("xmark.circle.fill", "Zip failed")
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
