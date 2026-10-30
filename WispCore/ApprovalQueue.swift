import Foundation

/// Permission requests in arrival order. The front one is on screen and stays there
/// until it's answered or times out, so a click can't land on a card that just swapped in.
public struct ApprovalQueue<ID: Hashable & Sendable>: Sendable {
    public private(set) var items: [ID] = []

    public init() {}

    public var front: ID? { items.first }

    public mutating func enqueue(_ id: ID) {
        guard !items.contains(id) else { return }
        items.append(id)
    }

    public mutating func remove(_ id: ID) {
        items.removeAll { $0 == id }
    }

    /// "1 of 2" while more than one request waits.
    public var positionLabel: String? {
        items.count > 1 ? "1 of \(items.count)" : nil
    }
}
