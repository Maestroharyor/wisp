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
}
