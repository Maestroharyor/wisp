import CoreGraphics
import Foundation

/// What a ring segment or sub-ring entry shows.
public enum RingIcon: Equatable, Hashable, Sendable {
    case symbol(String)
    /// The icon of the app with this bundle identifier.
    case app(bundleID: String)
    /// The icon Finder shows for this file or folder.
    case file(path: String)
}

/// Web addresses and app links a ring segment may open. Typed addresses gain `https://`;
/// local files and scripts are refused, since a link segment should only ever open a page or
/// hand a link to the app that owns it.
public enum RingLinks {
    private static let refused: Set<String> = ["file", "javascript", "data", "vbscript"]
    /// Schemes written without `//`, which can't be told apart from `host:port` otherwise.
    private static let opaque: Set<String> = ["mailto", "tel", "sms", "facetime", "facetime-audio"]

    public static func normalised(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let lowered = trimmed.lowercased()
        let scheme = lowered.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        // A scheme is letters at the very start followed by "://", or one of the few written
        // without slashes; "example.com/?to=https://x" is a typed address.
        let hasScheme =
            lowered.wholeMatch(of: /[a-z][a-z0-9+.\-]*:\/\/.*/) != nil || opaque.contains(scheme)
            || refused.contains(scheme)
        guard let url = URL(string: hasScheme ? trimmed : "https://" + trimmed),
            let found = url.scheme?.lowercased(), !refused.contains(found)
        else { return nil }
        if found == "http" || found == "https" {
            guard let host = url.host(), !host.isEmpty, host.contains(".") || host == "localhost" else { return nil }
        }
        return url
    }
}

/// One item in a folder, as the folder sub-ring needs it.
public struct FolderEntry: Equatable, Sendable {
    public let name: String
    public let path: String
    public let modified: Date
    public let isHidden: Bool

    public init(name: String, path: String, modified: Date, isHidden: Bool) {
        self.name = name
        self.path = path
        self.modified = modified
        self.isHidden = isHidden
    }
}

/// A folder segment's sub-ring: the newest things in it, which can be opened or dragged out.
public enum FolderPeek {
    private static let prefix = "file:"
    /// Five fan out over a third of the ring; more would wrap round it.
    public static let limit = 5

    public static func newest(_ entries: [FolderEntry], limit: Int = limit) -> [FolderEntry] {
        Array(
            entries
                .filter { !$0.isHidden && !$0.name.hasPrefix(".") }
                .sorted { ($0.modified, $1.name) > ($1.modified, $0.name) }
                .prefix(limit))
    }

    public static func choices(for entries: [FolderEntry]) -> [RingChoice] {
        entries.map { RingChoice(id: prefix + $0.path, title: $0.name, icon: .file(path: $0.path)) }
    }

    /// The file a folder choice stands for; nil for any other choice.
    public static func path(of choice: RingChoice) -> String? {
        choice.id.hasPrefix(prefix) ? String(choice.id.dropFirst(prefix.count)) : nil
    }
}

/// The dot under an app segment, like the Dock's.
public enum RingRunState: Equatable, Sendable {
    case none
    case running
    case frontmost

    public static func dot(for action: RingAction, running: Set<String>, frontmost: String?) -> RingRunState {
        guard action.kind == .app, let id = action.value, running.contains(id) else { return .none }
        return id == frontmost ? .frontmost : .running
    }
}

/// The apps the orb shows as a small dock: the ring's app segments (with its running section
/// when that's on), then apps in sub-rings, each once. It's the same list as the ring's, so
/// arranging one arranges the other.
public enum RingDock {
    public static let size = 8

    public static func apps(in set: RingSet, limit: Int = size) -> [RingAction] {
        let candidates = set.slots.map(\.action) + set.slots.flatMap(\.group)
        var seen = Set<String>()
        var apps: [RingAction] = []
        for action in candidates where action.kind == .app {
            guard let id = action.value, !id.isEmpty, seen.insert(id).inserted else { continue }
            apps.append(action)
            if apps.count == limit { break }
        }
        return apps
    }
}

/// Names for files copied into a folder segment, the way Finder keeps both: "report 2.pdf".
public enum FolderDrop {
    /// Names are compared ignoring case, as the Mac's disks usually do.
    public static func name(for original: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(original.lowercased()) else { return original }
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }

    /// One name per file, none clashing with the folder or with each other.
    public static func names(for originals: [String], existing: Set<String>) -> [String] {
        var taken = existing
        return originals.map { original in
            let name = name(for: original, existing: taken)
            taken.insert(name)
            return name
        }
    }
}

/// Where the orb's dock sits: a row of app icons beside the orb, on whichever side has room,
/// kept on screen, with room above the row for the hovered app's name.
public enum OrbDockGeometry {
    public static let icon: CGFloat = 36
    public static let spacing: CGFloat = 8
    public static let padding: CGFloat = 8
    public static let gap: CGFloat = 10
    /// Room above the row for the name pill, and for an icon lifting on hover.
    public static let labelRoom: CGFloat = 34

    public static var rowHeight: CGFloat { icon + padding * 2 }

    public static func size(count: Int) -> CGSize {
        let count = CGFloat(max(count, 1))
        return CGSize(width: padding * 2 + count * icon + (count - 1) * spacing, height: rowHeight + labelRoom)
    }

    /// The panel: the row centred on the orb, the label room above it.
    public static func frame(orb: CGRect, count: Int, in visible: CGRect) -> CGRect {
        let size = size(count: count)
        let right = orb.maxX + gap
        let x = right + size.width <= visible.maxX ? right : orb.minX - gap - size.width
        let y = orb.midY - rowHeight / 2
        return CGRect(
            x: min(max(x, visible.minX), visible.maxX - size.width),
            y: min(max(y, visible.minY), visible.maxY - size.height), width: size.width, height: size.height)
    }
}
