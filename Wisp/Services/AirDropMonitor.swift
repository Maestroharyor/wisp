import Foundation
import OSLog
import WispCore

/// Follows files arriving by AirDrop. macOS publishes each incoming file's progress (the same
/// progress Finder draws on the file); Wisp subscribes to what's published in Downloads, keeps
/// only files being received, and reads their numbers twice a second while any are in flight.
/// It never lists the folder or opens a file.
@MainActor
final class AirDropMonitor {
    var onChange: (DownloadSummary?) -> Void = { _ in }
    var onFinish: (FinishedDownload) -> Void = { _ in }

    private var subscriber: Any?
    private let published = PublishedTransfers()
    private var tracker = AirDropTracker()
    private var lastSummary: DownloadSummary?
    private var pollTask: Task<Void, Never>?
    /// Files that arrived since the last card, shown together once arrivals pause.
    private var arrivals: [FinishedDownload] = []
    private var arrivalTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "airdrop")

    func start() {
        guard subscriber == nil else { return }
        let downloads = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        let published = self.published
        subscriber = Progress.addSubscriber(forFileURL: downloads) { [weak self] progress in
            guard let id = published.add(progress, at: .now) else { return nil }
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
        arrivalTask?.cancel()
        arrivalTask = nil
        arrivals = []
        tracker = AirDropTracker()
        if lastSummary != nil {
            lastSummary = nil
            onChange(nil)
        }
    }

    /// Reads now, and keeps reading while anything that may be an AirDrop is published.
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
        let finished = tracker.update(published.snapshots(now: now), now: now)
        if !finished.isEmpty { arrive(finished) }
        let summary = tracker.summary(now: now)
        guard summary != lastSummary else { return }
        lastSummary = summary
        onChange(summary)
    }

    /// Several files sent together finish one after another; one card says they're all in.
    private func arrive(_ files: [FinishedDownload]) {
        arrivals += files
        arrivalTask?.cancel()
        arrivalTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            let batch = self.arrivals
            self.arrivals = []
            self.arrivalTask = nil
            self.log.info("AirDrop received \(batch.count, privacy: .public) file(s)")
            if let card = AirDropArrivals.combine(batch) { self.onFinish(card) }
        }
    }
}

/// The file progress macOS has published in Downloads. Foundation calls the publishing
/// handlers on the main thread, but they aren't isolated to the main actor, so this is shared
/// through a lock. `@unchecked Sendable` is safe here: every stored property is only touched
/// while holding `lock`, and `Progress` documents its properties as safe to read from any thread.
private final class PublishedTransfers: @unchecked Sendable {
    private struct Entry {
        let progress: Progress
        let added: Date
    }

    private let lock = NSLock()
    private var items: [Int: Entry] = [:]
    /// How each withdrawn transfer last read, handed over once so the tracker sees how it ended
    /// even when it finished between two reads.
    private var withdrawn: [AirDropSnapshot] = []
    private var nextID = 0

    var isEmpty: Bool { lock.withLock { items.isEmpty && withdrawn.isEmpty } }

    /// Keeps file progress and returns its key. Whether it's being received is settled on
    /// later reads: a progress from another process gets its operation a moment after it's
    /// published.
    func add(_ progress: Progress, at time: Date) -> Int? {
        guard AirDropFilter.classify(kind: progress.kind, operation: Self.operation(of: progress)) != .ignored else {
            return nil
        }
        return lock.withLock {
            nextID += 1
            items[nextID] = Entry(progress: progress, added: time)
            return nextID
        }
    }

    func remove(_ id: Int) {
        lock.withLock {
            guard let entry = items.removeValue(forKey: id), let last = Self.snapshot(id, entry.progress) else {
                return
            }
            withdrawn.append(last)
        }
    }

    func removeAll() {
        lock.withLock {
            items.removeAll()
            withdrawn.removeAll()
        }
    }

    /// Every AirDrop in flight, plus the final reading of any withdrawn since last time. Other
    /// file progress is dropped once it's known not to be one, or after a few seconds unknown.
    func snapshots(now: Date) -> [AirDropSnapshot] {
        lock.withLock {
            var all = withdrawn
            withdrawn.removeAll()
            for (id, entry) in items {
                switch AirDropFilter.classify(kind: entry.progress.kind, operation: Self.operation(of: entry.progress))
                {
                case .receiving:
                    if let snapshot = Self.snapshot(id, entry.progress) { all.append(snapshot) }
                case .pending:
                    if now.timeIntervalSince(entry.added) > AirDropFilter.pendingFor { items[id] = nil }
                case .ignored:
                    items[id] = nil
                }
            }
            return all
        }
    }

    // A progress from another process carries its operation and file in `userInfo`, while its
    // `fileOperationKind` and `fileURL` accessors stay empty for a while. `userInfo` is untyped,
    // so each value is checked for the type Foundation documents for its key.
    private static func operation(of progress: Progress) -> Progress.FileOperationKind? {
        progress.fileOperationKind
            ?? (progress.userInfo[.fileOperationKindKey] as? String).map(Progress.FileOperationKind.init(rawValue:))
    }

    private static func snapshot(_ id: Int, _ progress: Progress) -> AirDropSnapshot? {
        guard AirDropFilter.accepts(kind: progress.kind, operation: operation(of: progress)),
            let url = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
        else { return nil }
        return AirDropSnapshot(
            id: String(id), name: url.lastPathComponent, folder: url.deletingLastPathComponent().path,
            completed: max(progress.completedUnitCount, 0),
            total: progress.totalUnitCount > 0 ? progress.totalUnitCount : nil,
            isFinished: progress.isFinished, isCancelled: progress.isCancelled, isOld: progress.isOld)
    }
}
