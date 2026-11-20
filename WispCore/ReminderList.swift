import Foundation

/// A reminder as the Reminders widget shows it: its title and when it's due, nothing else.
public struct ReminderItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?
    public let isCompleted: Bool

    public init(id: String, title: String, due: Date?, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
    }
}

/// The order the Reminders widget lists them in: overdue first, then due today, then later,
/// then undated, each oldest due first; done ones are left out.
public enum ReminderList {
    public static let limit = 20

    public static func ordered(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [ReminderItem] {
        let open = items.enumerated().filter { !$0.element.isCompleted }
        func group(_ item: ReminderItem) -> Int {
            guard let due = item.due else { return 3 }
            if due < now { return 0 }
            return calendar.isDate(due, inSameDayAs: now) ? 1 : 2
        }
        let sorted = open.sorted { a, b in
            let (ga, gb) = (group(a.element), group(b.element))
            if ga != gb { return ga < gb }
            if let da = a.element.due, let db = b.element.due, da != db { return da < db }
            return a.offset < b.offset
        }
        return Array(sorted.prefix(limit).map(\.element))
    }

    public static func isOverdue(_ item: ReminderItem, now: Date) -> Bool {
        guard let due = item.due, !item.isCompleted else { return false }
        return due < now
    }
}
