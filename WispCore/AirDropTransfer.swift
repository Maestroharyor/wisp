import Foundation

/// One incoming AirDrop as its published file progress reads at a moment: numbers and the
/// file's name only.
public struct AirDropSnapshot: Sendable, Equatable {
    public let id: String
    public let name: String
    public let folder: String
    public let completed: Int64
    public let total: Int64?
    public let isFinished: Bool
    public let isCancelled: Bool

    public init(
        id: String, name: String, folder: String, completed: Int64, total: Int64?, isFinished: Bool, isCancelled: Bool
    ) {
        self.id = id
        self.name = name
        self.folder = folder
        self.completed = completed
        self.total = total
        self.isFinished = isFinished
        self.isCancelled = isCancelled
    }
}

/// Which published file progress is an incoming AirDrop. Safari publishes `.downloading`,
/// which the download monitor already follows, and Finder publishes copies.
public enum AirDropFilter {
    public static func accepts(kind: ProgressKind?, operation: Progress.FileOperationKind?) -> Bool {
        kind == .file && operation == .receiving
    }
}

/// Follows incoming AirDrops across snapshots: progress, rate, stalls and arrival. Each update
/// is the full set of transfers published right now.
public struct AirDropTracker: Sendable {
    public let stallAfter: TimeInterval
    public let rateWindow: TimeInterval

    private struct Tracked: Sendable {
        var snapshot: AirDropSnapshot
        let firstSeen: Date
        var lastChange: Date
        var samples: [(date: Date, completed: Int64)]
    }

    private var tracked: [String: Tracked] = [:]
    /// Transfers already reported as finished or cancelled, so a lingering snapshot isn't
    /// shown or reported again.
    private var settled = Set<String>()

    public init(stallAfter: TimeInterval = 30, rateWindow: TimeInterval = 5) {
        self.stallAfter = stallAfter
        self.rateWindow = rateWindow
    }

    /// Takes every transfer published now and returns the ones that just arrived.
    public mutating func update(_ snapshots: [AirDropSnapshot], now: Date) -> [FinishedDownload] {
        let current = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var finished: [FinishedDownload] = []

        // A transfer is withdrawn when it ends; it arrived if it had everything by then.
        for (id, item) in tracked where current[id] == nil {
            tracked[id] = nil
            if Self.isComplete(item.snapshot) { finished.append(Self.finished(item.snapshot)) }
        }
        settled.formIntersection(current.keys)

        for (id, snapshot) in current where !settled.contains(id) {
            if snapshot.isCancelled || snapshot.isFinished {
                tracked[id] = nil
                settled.insert(id)
                if snapshot.isFinished, !snapshot.isCancelled { finished.append(Self.finished(snapshot)) }
                continue
            }
            if var item = tracked[id] {
                if snapshot.completed != item.snapshot.completed {
                    if snapshot.completed < item.snapshot.completed { item.samples.removeAll() }
                    item.lastChange = now
                }
                item.snapshot = snapshot
                item.samples.append((now, snapshot.completed))
                item.samples.removeAll { now.timeIntervalSince($0.date) > rateWindow }
                tracked[id] = item
            } else {
                tracked[id] = Tracked(
                    snapshot: snapshot, firstSeen: now, lastChange: now, samples: [(now, snapshot.completed)])
            }
        }
        return finished.sorted { $0.name < $1.name }
    }

    /// Transfers in progress, newest first.
    public func transfers(now: Date) -> [DownloadProgress] {
        tracked
            .sorted { ($0.value.firstSeen, $0.key) > ($1.value.firstSeen, $1.key) }
            .map { id, item in
                let stalled = now.timeIntervalSince(item.lastChange) >= stallAfter
                return DownloadProgress(
                    id: id, name: item.snapshot.name, received: item.snapshot.completed, total: item.snapshot.total,
                    bytesPerSecond: stalled ? nil : rate(of: item), isStalled: stalled)
            }
    }

    public func summary(now: Date) -> DownloadSummary? {
        let all = transfers(now: now)
        return all.first.map { DownloadSummary(primary: $0, count: all.count, origin: .airDrop) }
    }

    /// Whether anything is showing, so stalls need checking as time passes.
    public var isWatching: Bool { !tracked.isEmpty }

    private func rate(of item: Tracked) -> Double? {
        guard let first = item.samples.first, let last = item.samples.last else { return nil }
        let seconds = last.date.timeIntervalSince(first.date)
        guard seconds >= 1, last.completed >= first.completed else { return nil }
        return Double(last.completed - first.completed) / seconds
    }

    private static func isComplete(_ snapshot: AirDropSnapshot) -> Bool {
        guard !snapshot.isCancelled, let total = snapshot.total, total > 0 else { return false }
        return snapshot.completed >= total
    }

    private static func finished(_ snapshot: AirDropSnapshot) -> FinishedDownload {
        FinishedDownload(
            folder: snapshot.folder, name: snapshot.name, size: max(snapshot.completed, snapshot.total ?? 0),
            origin: .airDrop)
    }
}
