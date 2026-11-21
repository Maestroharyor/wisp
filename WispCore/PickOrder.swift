import Foundation

/// The order items were picked in, for lists whose selection is a plain set. Items stay where
/// they were first picked; new picks join the end in the list's order.
public enum PickOrder {
    public static func update<ID: Hashable>(_ order: [ID], selection: Set<ID>, listOrder: [ID]) -> [ID] {
        let kept = order.filter(selection.contains)
        let known = Set(kept)
        let added = listOrder.filter { selection.contains($0) && !known.contains($0) }
        let listed = Set(listOrder)
        // Picks the list doesn't show (and so can't order) go last.
        let unlisted = selection.subtracting(known).subtracting(listed)
        return kept + added + unlisted.sorted { "\($0)" < "\($1)" }
    }
}
