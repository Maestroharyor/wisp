import Foundation

/// Which browser family writes a partial file.
public enum PartialKind: String, Sendable, Equatable {
    /// Chrome, Edge, Brave, Arc and other Chromium browsers: `name.crdownload`.
    case chromium
    /// Safari: a `name.download` bundle holding the data and an Info.plist.
    case safari
    /// Firefox: `name.part`, often beside an empty placeholder of the final name.
    case firefox
}

/// A file name that a browser is still downloading into.
public struct PartialName: Sendable, Equatable {
    public let kind: PartialKind
    /// The name the file gets when it finishes; nil while Chrome hasn't confirmed it yet.
    public let finalName: String?

    public init(kind: PartialKind, finalName: String?) {
        self.kind = kind
        self.finalName = finalName
    }

    public init?(_ name: String) {
        guard !name.hasPrefix(".") else { return nil }
        let lowered = name.lowercased()
        let suffixes: [(String, PartialKind)] = [
            (".crdownload", .chromium), (".download", .safari), (".part", .firefox),
        ]
        guard let (suffix, kind) = suffixes.first(where: { lowered.hasSuffix($0.0) }) else { return nil }
        let base = String(name.dropLast(suffix.count))
        guard !base.isEmpty else { return nil }
        self.kind = kind
        self.finalName = kind == .chromium && Self.isUnconfirmed(base) ? nil : base
    }

    /// The final name's extension, lowercased, or empty when there is none.
    public var finalExtension: String { finalName.map(Self.fileExtension) ?? "" }

    /// A file name's extension, lowercased, or empty when there is none.
    public static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    /// Chrome's name before the user or the server settles one: "Unconfirmed 123456".
    private static func isUnconfirmed(_ base: String) -> Bool {
        let prefix = "Unconfirmed "
        guard base.hasPrefix(prefix) else { return false }
        let digits = base.dropFirst(prefix.count)
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }
}

/// One entry of a watched folder: only its name and size, never its contents.
public struct DownloadFile: Sendable, Equatable {
    public let folder: String
    public let name: String
    public let size: Int64
    /// The expected size when the browser records one (Safari's bundle Info.plist).
    public let total: Int64?

    public init(folder: String, name: String, size: Int64, total: Int64? = nil) {
        self.folder = folder
        self.name = name
        self.size = size
        self.total = total
    }
}

/// A download in progress as the pill shows it.
public struct DownloadProgress: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let received: Int64
    public let total: Int64?
    public let bytesPerSecond: Double?
    public let isStalled: Bool

    public init(
        id: String, name: String, received: Int64, total: Int64?, bytesPerSecond: Double?, isStalled: Bool
    ) {
        self.id = id
        self.name = name
        self.received = received
        self.total = total
        self.bytesPerSecond = bytesPerSecond
        self.isStalled = isStalled
    }

    /// Only when the total is really known; otherwise the pill stays indeterminate.
    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(Double(received) / Double(total), 1)
    }

    public var remaining: TimeInterval? {
        guard let total, total > 0, let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        return Double(max(total - received, 0)) / bytesPerSecond
    }
}

/// The newest download plus how many are running.
public struct DownloadSummary: Sendable, Equatable {
    public let primary: DownloadProgress
    public let count: Int

    public init(primary: DownloadProgress, count: Int) {
        self.primary = primary
        self.count = count
    }
}

/// A download whose partial file turned into its final file.
public struct FinishedDownload: Sendable, Equatable {
    public let folder: String
    public let name: String
    public let size: Int64

    public init(folder: String, name: String, size: Int64) {
        self.folder = folder
        self.name = name
        self.size = size
    }

    public var path: String { (folder as NSString).appendingPathComponent(name) }
}

/// Follows partial files across folder listings: progress, rate, stalls and completion.
/// It never reads a file; each update is a list of names and sizes and the time it was taken.
public struct DownloadTracker: Sendable {
    public let stallAfter: TimeInterval
    public let forgetAfter: TimeInterval
    public let rateWindow: TimeInterval

    private struct Tracked: Sendable {
        let partial: PartialName
        let folder: String
        let firstSeen: Date
        /// Appeared after watching began, so it's a real new download, not a leftover.
        let isNew: Bool
        var size: Int64
        var total: Int64?
        var hasGrown = false
        var lastChange: Date
        var samples: [(date: Date, size: Int64)]
    }

    private var tracked: [String: Tracked] = [:]
    /// Sizes of ordinary files from the last listing, to spot a final file appearing.
    private var known: [String: Int64] = [:]
    private var primed = false

    public init(stallAfter: TimeInterval = 30, forgetAfter: TimeInterval = 120, rateWindow: TimeInterval = 5) {
        self.stallAfter = stallAfter
        self.forgetAfter = forgetAfter
        self.rateWindow = rateWindow
    }

    /// Takes a full listing of every watched folder and returns the downloads that finished.
    public mutating func update(_ files: [DownloadFile], now: Date) -> [FinishedDownload] {
        var partials: [String: (DownloadFile, PartialName)] = [:]
        var ordinary: [String: DownloadFile] = [:]
        for file in files {
            let key = Self.key(file.folder, file.name)
            if let partial = PartialName(file.name) {
                partials[key] = (file, partial)
            } else {
                ordinary[key] = file
            }
        }

        var finished: [FinishedDownload] = []
        var claimed = Set<String>()
        for (key, item) in tracked where partials[key] == nil {
            tracked[key] = nil
            guard item.isNew || item.hasGrown,
                let done = finalFile(for: item, in: ordinary, excluding: claimed)
            else { continue }
            claimed.insert(Self.key(done.folder, done.name))
            finished.append(FinishedDownload(folder: done.folder, name: done.name, size: done.size))
        }

        for (key, (file, partial)) in partials {
            if var item = tracked[key] {
                if file.size != item.size {
                    if file.size < item.size { item.samples.removeAll() }
                    item.hasGrown = item.hasGrown || file.size > item.size
                    item.size = file.size
                    item.lastChange = now
                }
                item.total = file.total
                item.samples.append((now, file.size))
                item.samples.removeAll { now.timeIntervalSince($0.date) > rateWindow }
                tracked[key] = item
            } else {
                tracked[key] = Tracked(
                    partial: partial, folder: file.folder, firstSeen: now, isNew: primed,
                    size: file.size, total: file.total, lastChange: now, samples: [(now, file.size)])
            }
        }

        known = ordinary.mapValues(\.size)
        primed = true
        return finished.sorted { $0.name < $1.name }
    }

    /// Downloads worth showing, newest first.
    public func downloads(now: Date) -> [DownloadProgress] {
        tracked
            .filter { isVisible($0.value, now: now) }
            .sorted { ($0.value.firstSeen, $0.key) > ($1.value.firstSeen, $1.key) }
            .map { key, item in
                let stalled = now.timeIntervalSince(item.lastChange) >= stallAfter
                return DownloadProgress(
                    id: key, name: item.partial.finalName ?? "Download", received: item.size, total: item.total,
                    bytesPerSecond: stalled ? nil : rate(of: item), isStalled: stalled)
            }
    }

    public func summary(now: Date) -> DownloadSummary? {
        let all = downloads(now: now)
        return all.first.map { DownloadSummary(primary: $0, count: all.count) }
    }

    /// Whether anything shown needs regular size checks (progress and stalls move with time).
    public func isWatching(now: Date) -> Bool {
        tracked.values.contains { isVisible($0, now: now) }
    }

    private func isVisible(_ item: Tracked, now: Date) -> Bool {
        (item.isNew || item.hasGrown) && now.timeIntervalSince(item.lastChange) < forgetAfter
    }

    private func rate(of item: Tracked) -> Double? {
        guard let first = item.samples.first, let last = item.samples.last else { return nil }
        let seconds = last.date.timeIntervalSince(first.date)
        guard seconds >= 1, last.size >= first.size else { return nil }
        return Double(last.size - first.size) / seconds
    }

    /// The exact final name first. Only when the real name can't be known from the partial
    /// (Chrome's unconfirmed files, Firefox's random partial names) does it fall back to a file
    /// in the same folder that is new or was an empty placeholder, at least as big as the
    /// partial was, with the partial's extension when it has one.
    private func finalFile(for item: Tracked, in ordinary: [String: DownloadFile], excluding claimed: Set<String>)
        -> DownloadFile?
    {
        if let finalName = item.partial.finalName, let exact = ordinary[Self.key(item.folder, finalName)],
            exact.size > 0, !claimed.contains(Self.key(item.folder, finalName))
        {
            return exact
        }
        guard item.partial.finalName == nil || item.partial.kind == .firefox else { return nil }
        let wanted = item.partial.finalExtension
        return
            ordinary
            .filter { key, file in
                file.folder == item.folder && file.size > 0 && file.size >= item.size && !claimed.contains(key)
                    && (known[key] ?? 0) == 0 && (wanted.isEmpty || PartialName.fileExtension(file.name) == wanted)
            }
            .sorted { $0.key < $1.key }
            .first?.value
    }

    private static func key(_ folder: String, _ name: String) -> String {
        (folder as NSString).appendingPathComponent(name)
    }
}

/// Reads the expected size from a Safari `.download` bundle's Info.plist. Only the two
/// progress numbers are decoded; the rest of the plist (the address, for one) is skipped.
public enum SafariDownloadInfo {
    public static func total(from plist: Data) -> Int64? {
        guard let info = try? PropertyListDecoder().decode(Info.self, from: plist),
            let total = info.total, total > 0
        else { return nil }
        return total
    }

    private struct Info: Decodable {
        let total: Int64?

        enum CodingKeys: String, CodingKey {
            case total = "DownloadEntryProgressTotalToLoad"
        }
    }
}

/// Short text for sizes and the pill's value.
public enum DownloadText {
    /// Decimal units like Finder: "999 B", "1.5 KB", "12 MB".
    public static func bytes(_ count: Int64) -> String {
        let units = ["KB", "MB", "GB", "TB"]
        guard count >= 1_000 else { return "\(max(count, 0)) B" }
        var value = Double(count)
        var unit = "B"
        // Thresholds sit just under each boundary so rounding never shows "1000 KB" or "10.0 MB".
        for next in units where value >= 999.5 {
            value /= 1_000
            unit = next
        }
        return value < 9.95 ? String(format: "%.1f %@", value, unit) : "\(Int(value.rounded())) \(unit)"
    }

    public static func detail(_ progress: DownloadProgress) -> String {
        if progress.isStalled { return "Stalled" }
        if let fraction = progress.fraction { return "\(Int((fraction * 100).rounded(.down)))%" }
        if let rate = progress.bytesPerSecond, rate > 0 { return "\(bytes(Int64(rate)))/s" }
        return bytes(progress.received)
    }
}

/// The folders to watch: always Downloads, then the chosen ones, without repeats.
public enum DownloadFolders {
    public static func resolve(extra: [String], home: String) -> [String] {
        let downloads = (home as NSString).appendingPathComponent("Downloads")
        var seen = Set<String>()
        return ([downloads] + extra).compactMap { path in
            guard !path.isEmpty else { return nil }
            let standard = (path as NSString).standardizingPath
            return seen.insert(standard).inserted ? standard : nil
        }
    }
}
