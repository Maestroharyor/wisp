import Foundation
import OSLog
import Observation
import WispCore

/// Follows files arriving by AirDrop. macOS publishes each incoming file's progress (the same
/// progress Finder draws on the file); Wisp subscribes to what's published in Downloads, keeps
/// only files being received, and reads their numbers twice a second while any are published.
/// It never lists the folder or opens a file.
@MainActor
@Observable
final class AirDropMonitor {
    @ObservationIgnored var onChange: (DownloadSummary?) -> Void = { _ in }
    @ObservationIgnored var onFinish: (FinishedDownload) -> Void = { _ in }

    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private let published = PublishedTransfers()
    @ObservationIgnored private var tracker = AirDropTracker()
    @ObservationIgnored private var lastSummary: DownloadSummary?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "airdrop")

    func start() {
        guard subscriber == nil else { return }
        let downloads = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        let published = self.published
        subscriber = Progress.addSubscriber(forFileURL: downloads) { [weak self] progress in
            guard let id = published.add(progress) else { return nil }
            Task { @MainActor in self?.wake() }
            return {
                published.remove(id)
                Task { @MainActor in self?.wake() }
            }
        }
    }

    func stop() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        published.removeAll()
        pollTask?.cancel()
        pollTask = nil
        tracker = AirDropTracker()
        if lastSummary != nil {
            lastSummary = nil
            onChange(nil)
        }
    }

    /// Reads now, and keeps reading while a transfer is in flight.
    private func wake() {
        guard subscriber != nil else { return }
        read()
        guard pollTask == nil, isBusy else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.read()
                if !self.isBusy {
                    self.pollTask = nil
                    return
                }
            }
        }
    }

    private var isBusy: Bool { tracker.isWatching || !published.isEmpty }

    private func read() {
        let now = Date.now
        let finished = tracker.update(published.snapshots(), now: now)
        if !finished.isEmpty { log.info("AirDrop received \(finished.count, privacy: .public) file(s)") }
        for file in finished { onFinish(file) }
        let summary = tracker.summary(now: now)
        guard summary != lastSummary else { return }
        lastSummary = summary
        onChange(summary)
    }
}

/// The incoming transfers macOS has published, reachable from its callback queue and the main
/// actor. `@unchecked Sendable` is safe here: `items` is only touched while holding `lock`, and
/// `Progress` documents its properties as safe to read from any thread.
private final class PublishedTransfers: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int: Progress] = [:]
    /// How each withdrawn transfer last read, handed over once so the tracker sees how it ended
    /// even when it finished between two reads.
    private var withdrawn: [AirDropSnapshot] = []
    private var nextID = 0

    var isEmpty: Bool { lock.withLock { items.isEmpty && withdrawn.isEmpty } }

    /// Keeps file progress and returns its key. Whether it's being received is checked on each
    /// read: a progress from another process gets its operation and file a moment after it's
    /// published.
    func add(_ progress: Progress) -> Int? {
        guard progress.kind == .file else { return nil }
        return lock.withLock {
            nextID += 1
            items[nextID] = progress
            return nextID
        }
    }

    func remove(_ id: Int) {
        lock.withLock {
            guard let progress = items.removeValue(forKey: id), let last = Self.snapshot(id, progress) else { return }
            withdrawn.append(last)
        }
    }

    func removeAll() {
        lock.withLock {
            items.removeAll()
            withdrawn.removeAll()
        }
    }

    /// Every transfer published now, plus the final reading of any withdrawn since last time.
    func snapshots() -> [AirDropSnapshot] {
        lock.withLock {
            let all = items.compactMap { Self.snapshot($0.key, $0.value) } + withdrawn
            withdrawn.removeAll()
            return all
        }
    }

    private static func snapshot(_ id: Int, _ progress: Progress) -> AirDropSnapshot? {
        // A progress from another process carries these in `userInfo`, while its `fileURL` and
        // `fileOperationKind` accessors can stay empty. `userInfo` is untyped, so each value is
        // checked for the type Foundation documents for its key.
        let info = progress.userInfo
        let operation = (info[.fileOperationKindKey] as? String).map(Progress.FileOperationKind.init(rawValue:))
        guard AirDropFilter.accepts(kind: progress.kind, operation: operation),
            let url = info[.fileURLKey] as? URL
        else { return nil }
        return AirDropSnapshot(
            id: String(id), name: url.lastPathComponent, folder: url.deletingLastPathComponent().path,
            completed: max(progress.completedUnitCount, 0),
            total: progress.totalUnitCount > 0 ? progress.totalUnitCount : nil,
            isFinished: progress.isFinished, isCancelled: progress.isCancelled)
    }
}
