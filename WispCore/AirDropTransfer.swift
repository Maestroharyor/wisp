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
    /// Published before Wisp was watching, so its arrival isn't news.
    public let isOld: Bool

    public init(
        id: String, name: String, folder: String, completed: Int64, total: Int64?, isFinished: Bool, isCancelled: Bool,
        isOld: Bool = false
    ) {
        self.id = id
        self.name = name
        self.folder = folder
        self.completed = completed
        self.total = total
        self.isFinished = isFinished
        self.isCancelled = isCancelled
        self.isOld = isOld
    }
}

/// Which published file progress is an incoming AirDrop. Safari publishes `.downloading`,
/// which the download monitor already follows, and Finder publishes copies.
public enum AirDropFilter {
    public enum Intake: Sendable, Equatable {
        case receiving
        /// A file progress whose operation hasn't arrived yet: one from another process gets
        /// it a moment after it's published.
        case pending
        /// Something else: dropped, so a browser download doesn't keep Wisp reading.
        case ignored
    }

    /// How long a file progress may stay `pending` before it's given up on.
    public static let pendingFor: TimeInterval = 3

    public static func accepts(kind: ProgressKind?, operation: Progress.FileOperationKind?) -> Bool {
        classify(kind: kind, operation: operation) == .receiving
    }

    public static func classify(kind: ProgressKind?, operation: Progress.FileOperationKind?) -> Intake {
        guard kind == .file else { return .ignored }
        guard let operation else { return .pending }
        return operation == .receiving ? .receiving : .ignored
    }
}

/// Files that arrive together make one card: "3 items" in their folder, not a card per file
/// replacing the last.
public enum AirDropArrivals {
    /// The deepest folder holding them all.
    static func commonFolder(_ folders: [String]) -> String {
        let paths = folders.map { ($0 as NSString).pathComponents }
        guard var shared = paths.first else { return "/" }
        for path in paths.dropFirst() {
            shared = Array(zip(shared, path).prefix { $0 == $1 }.map(\.0))
        }
        return shared.isEmpty ? "/" : NSString.path(withComponents: shared)
    }

    public static func combine(_ files: [FinishedDownload]) -> FinishedDownload? {
        guard let first = files.first else { return nil }
        guard files.count > 1 else { return first }
        let folder = commonFolder(files.map(\.folder))
        return FinishedDownload(
            folder: folder, name: "\(files.count) items", size: files.reduce(0) { $0 + $1.size }, origin: .airDrop,
            itemCount: files.count)
    }
}

/// Follows incoming AirDrops across snapshots: progress, rate, stalls and arrival. Each update
/// is the full set of transfers published right now.
public struct AirDropTracker: Sendable {
    public let stallAfter: TimeInterval
    public let rateWindow: TimeInterval
    /// How long a transfer may go without progress before it's dropped altogether.
    public let forgetAfter: TimeInterval

    private struct Tracked: Sendable {
        var snapshot: AirDropSnapshot
        let firstSeen: Date
        /// Breaks ties between transfers first seen together, oldest first.
        let order: Int
        var lastChange: Date
        var samples: [(date: Date, completed: Int64)]
    }

    private var tracked: [String: Tracked] = [:]
    /// Transfers already reported as finished or cancelled, so a lingering snapshot isn't
    /// shown or reported again.
    private var settled = Set<String>()
    private var seen = 0

    public init(stallAfter: TimeInterval = 30, rateWindow: TimeInterval = 5, forgetAfter: TimeInterval = 120) {
        self.stallAfter = stallAfter
        self.rateWindow = rateWindow
        self.forgetAfter = forgetAfter
    }

    /// Takes every transfer published now and returns the ones that just arrived.
    public mutating func update(_ snapshots: [AirDropSnapshot], now: Date) -> [FinishedDownload] {
        // In the order given, so transfers first seen together are ordered the same every time;
        // a repeated id keeps its last reading.
        var order: [String] = []
        var current: [String: AirDropSnapshot] = [:]
        for snapshot in snapshots {
            if current[snapshot.id] == nil { order.append(snapshot.id) }
            current[snapshot.id] = snapshot
        }
        var finished: [FinishedDownload] = []

        // A transfer is withdrawn when it ends; it arrived if it had everything by then.
        for (id, item) in tracked where current[id] == nil {
            tracked[id] = nil
            if Self.isComplete(item.snapshot), !item.snapshot.isOld { finished.append(Self.finished(item.snapshot)) }
        }
        settled.formIntersection(current.keys)

        for id in order where !settled.contains(id) {
            guard let snapshot = current[id] else { continue }
            if snapshot.isCancelled || snapshot.isFinished {
                tracked[id] = nil
                settled.insert(id)
                if snapshot.isFinished, !snapshot.isCancelled, !snapshot.isOld {
                    finished.append(Self.finished(snapshot))
                }
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
                seen += 1
                tracked[id] = Tracked(
                    snapshot: snapshot, firstSeen: now, order: seen, lastChange: now,
                    samples: [(now, snapshot.completed)])
            }
        }
        // A transfer that hasn't moved for this long (the sender walked away, or macOS left
        // its progress behind) is dropped, so its pill and the polling don't stay for good.
        for (id, item) in tracked where now.timeIntervalSince(item.lastChange) >= forgetAfter {
            tracked[id] = nil
            settled.insert(id)
        }
        return finished.sorted { $0.name < $1.name }
    }

    /// Transfers in progress, newest first.
    public func transfers(now: Date) -> [DownloadProgress] {
        tracked
            .sorted { ($0.value.firstSeen, $0.value.order) > ($1.value.firstSeen, $1.value.order) }
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
