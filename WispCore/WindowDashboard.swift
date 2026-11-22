import Foundation

/// The window's Home header: a greeting for the time of day and the colours behind it.
public enum WindowGreeting {
    public struct Palette: Equatable, Sendable {
        public let leading: RGB
        public let trailing: RGB
    }

    public static func greeting(hour: Int) -> String {
        switch part(of: hour) {
        case .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening: "Good evening"
        case .night: "Good night"
        }
    }

    /// "Good morning, Ada": the first word of the account's full name, or no name when it has none.
    public static func greeting(hour: Int, fullName: String) -> String {
        let first = fullName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? greeting(hour: hour) : "\(greeting(hour: hour)), \(first)"
    }

    /// Dawn peach, day sky, dusk rose or night indigo, each easing into Wisp's violet. Light
    /// palettes are pale washes; dark ones are deep, so white text reads on them.
    public static func palette(hour: Int, isDark: Bool) -> Palette {
        let (leading, trailing): (RGB, RGB) =
            switch part(of: hour) {
            case .morning: (RGB(red: 1, green: 0.72, blue: 0.55), violet)
            case .afternoon: (RGB(red: 0.45, green: 0.7, blue: 1), violet)
            case .evening: (RGB(red: 0.95, green: 0.5, blue: 0.6), RGB(red: 0.36, green: 0.3, blue: 0.85))
            case .night: (RGB(red: 0.3, green: 0.3, blue: 0.75), RGB(red: 0.12, green: 0.1, blue: 0.3))
            }
        return isDark
            ? Palette(leading: scaled(leading, 0.45), trailing: scaled(trailing, 0.4))
            : Palette(leading: towardWhite(leading, 0.6), trailing: towardWhite(trailing, 0.7))
    }

    private enum Part { case morning, afternoon, evening, night }

    private static func part(of hour: Int) -> Part {
        switch ((hour % 24) + 24) % 24 {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default: .night
        }
    }

    private static let violet = RGB(red: 0.48, green: 0.42, blue: 1)

    private static func scaled(_ colour: RGB, _ amount: Double) -> RGB {
        RGB(red: colour.red * amount, green: colour.green * amount, blue: colour.blue * amount)
    }

    private static func towardWhite(_ colour: RGB, _ amount: Double) -> RGB {
        TimeOfDayTint.mix(colour, .white, amount)
    }
}

extension RGB {
    /// Relative brightness, 0 to 1, weighted as the eye sees the channels.
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

/// The days the window's Home lists: today and the six after it, the days the calendar reads.
public enum WeekStrip {
    public static func days(from now: Date, count: Int = 7, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 0)).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// The day `step` days from `day` in `days`, kept within the strip. Nil stands for the
    /// first day (today), both given and returned.
    public static func stepped(_ day: Date?, by step: Int, in days: [Date], calendar: Calendar) -> Date? {
        guard !days.isEmpty else { return nil }
        let current = day.flatMap { day in days.firstIndex { calendar.isDate($0, inSameDayAs: day) } } ?? 0
        let next = min(max(current + step, 0), days.count - 1)
        return next == 0 ? nil : days[next]
    }
}

/// The cards on the window's Home, in the order chosen.
public enum HomeCard: String, CaseIterable, Identifiable, Sendable {
    case events
    case reminders
    case agents
    case notes

    public var id: Self { self }

    public var title: String {
        switch self {
        case .events: "Events"
        case .reminders: "Reminders"
        case .agents: "Agents"
        case .notes: "Notes"
        }
    }

    public static let standard: [HomeCard] = [.events, .reminders, .agents]

    /// The saved cards, without names this version doesn't know or repeats; nothing saved yet
    /// is the standard set.
    public static func read(_ stored: [String]?) -> [HomeCard] {
        guard let stored else { return standard }
        var seen = Set<HomeCard>()
        return stored.compactMap(HomeCard.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    /// Shown cards with `card` added at the end, or taken out when it's there.
    public static func toggled(_ card: HomeCard, in cards: [HomeCard]) -> [HomeCard] {
        cards.contains(card) ? cards.filter { $0 != card } : cards + [card]
    }

    /// `cards` after a list drag (SwiftUI's `onMove` indices).
    public static func moved(_ cards: [HomeCard], from source: IndexSet, to destination: Int) -> [HomeCard] {
        let moving = source.sorted().compactMap { cards.indices.contains($0) ? cards[$0] : nil }
        var rest = cards.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        let at = min(max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: at)
        return rest
    }
}

extension WindowLayout {
    /// The Home dashboard's card columns: one when narrow, two from 620, three from 980.
    public static func dashboardColumns(width: Double) -> Int {
        switch width {
        case ..<620: 1
        case ..<980: 2
        default: 3
        }
    }
}
