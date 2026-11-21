import Foundation

/// A reminder as the Reminders widget shows it: its title and when it's due, nothing else.
public struct ReminderItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?
    public let isCompleted: Bool
    /// The Reminders list it's in, and that list's colour.
    public let list: String
    public let listColor: RGB?

    public init(
        id: String, title: String, due: Date?, isCompleted: Bool, list: String = "", listColor: RGB? = nil
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
        self.list = list
        self.listColor = listColor
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

/// A Reminders list as the window's Reminders page shows it: its name, colour and how many
/// open reminders it holds.
public struct ReminderListSummary: Equatable, Identifiable, Sendable {
    public let name: String
    public let color: RGB?
    public let count: Int
    public var id: String { name }

    /// Lists in order of how many reminders they hold, then by name; reminders without a list
    /// are left out.
    public static func summaries(_ items: [ReminderItem]) -> [ReminderListSummary] {
        let groups = Dictionary(grouping: items.filter { !$0.list.isEmpty }, by: \.list)
        return groups.map { name, items in
            ReminderListSummary(name: name, color: items.first?.listColor, count: items.count)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
