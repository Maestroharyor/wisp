import Foundation

/// Spots permissions granted since the last check, so Wisp can come back to the front.
public enum PermissionWatch {
    /// Ids that were not granted (or unknown) before and are granted now, sorted.
    public static func newlyGranted(before: [String: Bool?], after: [String: Bool?]) -> [String] {
        after.compactMap { id, status in
            status == .some(true) && before[id] != .some(true) ? id : nil
        }
        .sorted()
    }

    /// How long after an Allow click a grant still counts as the answer to it.
    public static let requestWindow: TimeInterval = 5 * 60

    /// Only grants that answer a recent Allow bring Wisp forward. Others (System Events
    /// starting, a grant made elsewhere) must not take focus from whatever the person is doing.
    public static func shouldBringForward(newlyGranted: [String], lastRequest: Date?, now: Date) -> Bool {
        guard !newlyGranted.isEmpty, let lastRequest else { return false }
        return now.timeIntervalSince(lastRequest) <= requestWindow
    }
}
