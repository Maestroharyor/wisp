import CoreServices
import Foundation
import OSLog
import Observation
import WispCore

/// Watches Downloads and the chosen folders for browsers' partial files and reports
/// progress and finished downloads. FSEvents wakes it when a folder changes; while a
/// download shows, it also checks sizes every second, since a growing file doesn't
/// reliably produce events. It lists names and sizes only and never opens a download,
/// apart from the two progress numbers in a Safari bundle's Info.plist.
@MainActor
@Observable
final class DownloadMonitor {
    @ObservationIgnored var onChange: (DownloadSummary?) -> Void = { _ in }
    @ObservationIgnored var onFinish: (FinishedDownload) -> Void = { _ in }

    /// Watched folders macOS wouldn't let Wisp list, for Settings to explain.
    private(set) var deniedFolders: [String] = []
    /// Every download in progress, newest first, for the list the pill opens.
    private(set) var downloads: [DownloadProgress] = []

    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var folders: [String] = []
    @ObservationIgnored private var tracker = DownloadTracker()
    @ObservationIgnored private var lastSummary: DownloadSummary?
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var rescan = false
    /// Bumped on every start and stop, so a listing begun for earlier folders is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "downloads")

    /// Starts watching, or switches to a new set of folders.
    func start(folders: [String]) {
        guard folders != self.folders || stream == nil else { return }
        stop()
        self.folders = folders
        tracker = DownloadTracker()
        startStream()
        scan()
    }

    func stop() {
        generation += 1
        scanning = false
        rescan = false
        pollTask?.cancel()
        pollTask = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        folders = []
        if !deniedFolders.isEmpty { deniedFolders = [] }
        if !downloads.isEmpty { downloads = [] }
        if lastSummary != nil {
            lastSummary = nil
            onChange(nil)
        }
    }

    private func startStream() {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        // The callback runs on the main queue (set below), and `stop()` invalidates the
        // stream before the monitor could go away, so the unretained pointer stays valid.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<DownloadMonitor>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.scan() }
        }
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, folders as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        else {
            log.error("Couldn't watch the download folders")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func scan() {
        guard !scanning else {
            rescan = true
            return
        }
        scanning = true
        let folders = self.folders
        let generation = self.generation
        Task { [weak self] in
            let listing = await Self.list(folders)
            self?.apply(listing, generation: generation)
        }
    }

    private func apply(_ listing: Listing, generation: Int) {
        guard generation == self.generation else { return }
        scanning = false
        guard stream != nil else { return }
        if listing.denied != deniedFolders { deniedFolders = listing.denied }
        let now = Date.now
        let finished = tracker.update(listing.files, now: now)
        for download in finished { onFinish(download) }
        publish(now: now)
        updatePolling(now: now)
        if rescan {
            rescan = false
            scan()
        }
    }

    private func publish(now: Date) {
        let all = tracker.downloads(now: now)
        if all != downloads { downloads = all }
        let summary = all.first.map { DownloadSummary(primary: $0, count: all.count) }
        guard summary != lastSummary else { return }
        lastSummary = summary
        onChange(summary)
    }

    private func updatePolling(now: Date) {
        guard tracker.isWatching(now: now) else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.scan()
            }
        }
    }

    private struct Listing: Sendable {
        var files: [DownloadFile] = []
        var denied: [String] = []
    }

    /// Names and sizes of each folder's top-level entries, off the main thread.
    private nonisolated static func list(_ folders: [String]) async -> Listing {
        await Task.detached(priority: .utility) {
            var listing = Listing()
            for folder in folders {
                do {
                    listing.files += try entries(in: folder)
                } catch let error as CocoaError where error.code == .fileReadNoPermission {
                    listing.denied.append(folder)
                } catch {
                    // A folder that's gone or unreadable for another reason simply lists nothing.
                }
            }
            return listing
        }.value
    }

    private nonisolated static func entries(in folder: String) throws -> [DownloadFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: folder, isDirectory: true), includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles])
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            if values?.isDirectory == true, PartialName(name)?.kind == .safari {
                return DownloadFile(
                    folder: folder, name: name, size: bundleSize(url),
                    total: (try? Data(contentsOf: url.appendingPathComponent("Info.plist"))).flatMap(
                        SafariDownloadInfo.total(from:)))
            }
            return DownloadFile(folder: folder, name: name, size: Int64(values?.fileSize ?? 0))
        }
    }

    /// The data a Safari bundle holds so far: its files other than Info.plist.
    private nonisolated static func bundleSize(_ bundle: URL) -> Int64 {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: bundle, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return 0 }
        return urls.filter { $0.lastPathComponent != "Info.plist" }
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
    }
}
