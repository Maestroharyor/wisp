import Foundation

/// Which permissions Wisp's switched-on features need but doesn't have.
public enum SetupHealth {
    /// Permission ids the current features need, in display order.
    public static func needed(notifications: Bool, calendarWidgets: Bool, mirror: Bool) -> [String] {
        var ids = ["accessibility"]
        if notifications { ids.append("fullDiskAccess") }
        if calendarWidgets { ids.append("calendars") }
        if mirror { ids.append("camera") }
        return ids
    }

    /// Needed permissions known to be missing. Unknown (nil) statuses don't count.
    public static func missing(granted: [String: Bool?], needed: [String]) -> [String] {
        needed.filter { granted[$0] == .some(false) }
    }
}
