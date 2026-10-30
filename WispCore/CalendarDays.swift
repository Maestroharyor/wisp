import Foundation

/// Groups calendar items into days with short headers: "Today", "Tomorrow", "Mon 2".
public enum CalendarDays {
    public struct Day<Item> {
        public let label: String
        public let items: [Item]
    }

    public static func label(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter.string(from: date)
    }

    /// Items sorted by date and grouped into consecutive days.
    public static func group<Item>(
        _ items: [Item], date: (Item) -> Date, now: Date, calendar: Calendar = .current
    ) -> [Day<Item>] {
        var days: [(start: Date, items: [Item])] = []
        for item in items.sorted(by: { date($0) < date($1) }) {
            let start = calendar.startOfDay(for: date(item))
            if let last = days.indices.last, days[last].start == start {
                days[last].items.append(item)
            } else {
                days.append((start, [item]))
            }
        }
        return days.map { Day(label: label(for: $0.start, now: now, calendar: calendar), items: $0.items) }
    }
}
