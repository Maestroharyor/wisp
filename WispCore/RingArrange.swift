import CoreGraphics
import Foundation

/// Rearranging the open ring by hand, as with the Dock: drag an icon to another place, drag it
/// off the ring to take it away, or drop an app on the ring to add it.
public enum RingArrange {
    /// How far past the band an icon must be dragged to come off the ring.
    public static let removeBeyond: CGFloat = RingGeometry.ringOuter + 40

    /// Where a dragged icon lands, from the direction it's dropped in.
    public static func index(at angle: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return RingFlick.slot(at: RingGeometry.normalised(angle), slots: count)
    }

    /// The slots with the one at `from` moved to `to`.
    public static func move(_ slots: [RingSlot], from: Int, to: Int) -> [RingSlot] {
        guard slots.indices.contains(from) else { return slots }
        var moved = slots
        let slot = moved.remove(at: from)
        moved.insert(slot, at: min(max(to, 0), moved.count))
        return moved
    }

    public static func remove(_ slots: [RingSlot], at index: Int) -> [RingSlot] {
        guard slots.indices.contains(index) else { return slots }
        var kept = slots
        kept.remove(at: index)
        return kept
    }

    public enum Insertion: Equatable, Sendable {
        case added([RingSlot])
        /// Every app, link or folder given is on the ring already.
        case alreadyThere
        case full
    }

    /// The slots with `actions` added at `index`, leaving out apps, links and folders already on the ring and
    /// stopping when it's full.
    public static func insert(_ actions: [RingAction], into slots: [RingSlot], at index: Int) -> Insertion {
        // Apps, links and folders are one place each; other actions can repeat.
        func key(_ action: RingAction) -> String? {
            guard [.app, .link, .folder].contains(action.kind), let value = action.value else { return nil }
            return "\(action.kind.rawValue):\(value)"
        }
        let present = Set(slots.compactMap { key($0.action) })
        var seen = Set<String>()
        let fresh = actions.filter { action in
            guard let key = key(action) else { return true }
            return !present.contains(key) && seen.insert(key).inserted
        }
        guard !fresh.isEmpty else { return .alreadyThere }
        let room = RingSet.maxSlots - slots.count
        guard room > 0 else { return .full }
        var added = slots
        added.insert(contentsOf: fresh.prefix(room).map { RingSlot($0) }, at: min(max(index, 0), slots.count))
        return .added(added)
    }
}

/// Files dropped on the ring that are all apps are pinned to it, unless they land on a folder,
/// which copies whatever it's given.
public enum RingPinDrop {
    public static func pins(paths: [String], onto target: RingAction.Kind?) -> Bool {
        guard !paths.isEmpty, target != .folder else { return false }
        return paths.allSatisfy { ($0 as NSString).pathExtension.lowercased() == "app" }
    }
}

/// An app that's running, as the ring's running section lists it.
public struct RunningApp: Equatable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// The ring's running section: apps that are open but not pinned fill the free places after
/// the pinned ones, in the order they were opened, as the Dock shows them.
public enum RingRunning {
    public static func fill(_ pinned: [RingSlot], running: [RunningApp], limit: Int = RingSet.maxSlots)
        -> [RingSlot]
    {
        var taken = Set(pinned.compactMap { $0.action.kind == .app ? $0.action.value : nil })
        var slots = pinned
        for app in running where slots.count < limit {
            guard !app.bundleID.isEmpty, taken.insert(app.bundleID).inserted else { continue }
            slots.append(RingSlot(RingAction(.app, value: app.bundleID, label: app.name)))
        }
        return slots
    }
}
