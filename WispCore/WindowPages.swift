import Foundation

// MARK: Week grid

/// Lays out a day's timed events in the window's hour grid: side by side where they overlap,
/// placed by their times.
public enum WeekGrid {
    public struct Placed: Equatable, Sendable {
        /// Which column of its overlapping group the event takes, from 0.
        public let lane: Int
        /// How many columns its overlapping group needs.
        public let lanes: Int
    }

    /// The shortest an event is drawn, so its title still fits.
    public static let minimumHeight: Double = 22

    /// A lane for each event, in the order given. Events that overlap, directly or through a
    /// chain, form a group sharing its widest number of lanes; a lane frees up when its event ends.
    public static func lanes(_ events: [ClosedRange<Date>]) -> [Placed] {
        let order = events.indices.sorted { events[$0].lowerBound < events[$1].lowerBound }
        var lane = [Int](repeating: 0, count: events.count)
        var lanes = [Int](repeating: 1, count: events.count)
        var group: [Int] = []
        var laneEnds: [Date] = []
        var groupEnd = Date.distantPast

        func close() {
            for index in group { lanes[index] = max(laneEnds.count, 1) }
            group = []
            laneEnds = []
        }

        for index in order {
            let event = events[index]
            if !group.isEmpty, event.lowerBound >= groupEnd { close() }
            if let free = laneEnds.firstIndex(where: { $0 <= event.lowerBound }) {
                lane[index] = free
                laneEnds[free] = event.upperBound
            } else {
                lane[index] = laneEnds.count
                laneEnds.append(event.upperBound)
            }
            group.append(index)
            groupEnd = group.count == 1 ? event.upperBound : max(groupEnd, event.upperBound)
        }
        close()
        return events.indices.map { Placed(lane: lane[$0], lanes: lanes[$0]) }
    }

    /// The hours the grid shows: the working hours with an hour either side, widened to take in
    /// every event.
    public static func hours(events: [ClosedRange<Date>], working: ClosedRange<Int>, calendar: Calendar)
        -> ClosedRange<Int>
    {
        var low = max(working.lowerBound - 1, 0)
        var high = min(working.upperBound + 1, 24)
        for event in events {
            low = min(low, calendar.component(.hour, from: event.lowerBound))
            let end = calendar.dateComponents([.hour, .minute], from: event.upperBound)
            let endHour = (end.hour ?? 0) + ((end.minute ?? 0) > 0 ? 1 : 0)
            let sameDay = calendar.isDate(event.lowerBound, inSameDayAs: event.upperBound)
            high = max(high, sameDay ? endHour : 24)
        }
        return low...min(high, 24)
    }

    /// Where an event sits in a day's column: points from the top of the first hour shown, and
    /// its height.
    public static func frame(
        for event: ClosedRange<Date>, dayStart: Date, hours: ClosedRange<Int>, hourHeight: Double
    ) -> (top: Double, height: Double) {
        let first = dayStart.addingTimeInterval(Double(hours.lowerBound) * 3_600)
        let last = dayStart.addingTimeInterval(Double(hours.upperBound) * 3_600)
        let start = min(max(event.lowerBound, first), last)
        let end = min(max(event.upperBound, start), last)
        let top = start.timeIntervalSince(first) / 3_600 * hourHeight
        let height = end.timeIntervalSince(start) / 3_600 * hourHeight
        return (top, max(height, minimumHeight))
    }
}

/// How the window's Calendar page shows the week.
public enum CalendarLayout: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case agenda

    public var id: Self { self }

    public var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .agenda: "Agenda"
        }
    }
}

// MARK: Notes

/// One note: its text, when it was last changed and whether it's pinned to the top.
public struct Note: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var body: String
    public var updated: Date
    public var pinned: Bool

    public init(id: UUID = UUID(), body: String, updated: Date, pinned: Bool = false) {
        self.id = id
        self.body = body
        self.updated = updated
        self.pinned = pinned
    }

    private var lines: [String] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The first line with text in it, cut to 60 characters; "New note" for an empty note.
    public var title: String {
        lines.first.map { String($0.prefix(60)) } ?? "New note"
    }

    /// The line after the title, for the list.
    public var preview: String {
        lines.dropFirst().first ?? ""
    }

    public var isEmpty: Bool { lines.isEmpty }
}

/// Every note, kept on this Mac.
public struct NoteBook: Codable, Equatable, Sendable {
    public private(set) var notes: [Note] = []

    public init() {}

    /// Pinned first, then the most recently changed.
    public var sorted: [Note] {
        notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updated > b.updated
        }
    }

    public func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    public mutating func add(body: String = "", at date: Date) -> UUID {
        let note = Note(body: body, updated: date)
        notes.append(note)
        return note.id
    }

    public mutating func update(_ id: UUID, body: String, at date: Date) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].body != body else { return }
        notes[index].body = body
        notes[index].updated = date
    }

    public mutating func remove(_ id: UUID) {
        notes.removeAll { $0.id == id }
    }

    /// Puts a removed note back, for Undo.
    public mutating func restore(_ note: Note) {
        guard self.note(note.id) == nil else { return }
        notes.append(note)
    }

    public mutating func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].pinned.toggle()
    }

    /// Sorted notes whose text contains `query`, ignoring case and accents; all of them for an
    /// empty query.
    public func search(_ query: String) -> [Note] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The single scratch note of earlier versions as the first note, or no notes when it was empty.
    public static func migrated(fromSingle text: String, at date: Date) -> NoteBook {
        var book = NoteBook()
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { book.add(body: text, at: date) }
        return book
    }
}

// MARK: Reminders

/// The Reminders page's stat tiles, each a filter over the open reminders.
public enum ReminderFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case today
    case overdue
    case scheduled

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .overdue: "Overdue"
        case .scheduled: "Scheduled"
        }
    }

    public func apply(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [ReminderItem] {
        items.filter { item in
            switch self {
            case .all: true
            case .today: item.due.map { $0 >= now && calendar.isDate($0, inSameDayAs: now) } ?? false
            case .overdue: ReminderList.isOverdue(item, now: now)
            case .scheduled: item.due != nil
            }
        }
    }

    public func count(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> Int {
        apply(items, now: now, calendar: calendar).count
    }
}

// MARK: Clipboard

/// How many clips there are of each kind, for the Clipboard page's filter.
public struct ClipCounts: Equatable, Sendable {
    public let all: Int
    private let byKind: [ClipKind: Int]

    public init(_ items: [ClipItem]) {
        all = items.count
        byKind = Dictionary(grouping: items, by: \.kind).mapValues(\.count)
    }

    public subscript(kind: ClipKind) -> Int { byKind[kind] ?? 0 }
}

extension ClipCounts {
    /// One source app and how many clips came from it.
    public struct App: Equatable, Identifiable, Sendable {
        public let name: String
        public let bundleID: String?
        public let count: Int
        public var id: String { name }
    }

    /// The apps clips were copied from, most clips first, then by name. Clips with no known
    /// source are left out.
    public static func apps(_ items: [ClipItem]) -> [App] {
        let groups = Dictionary(grouping: items.filter { !($0.sourceApp ?? "").isEmpty }) { $0.sourceApp ?? "" }
        return groups.map { name, items in
            App(name: name, bundleID: items.first { $0.sourceBundleID != nil }?.sourceBundleID, count: items.count)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}

/// How a clip's text is shown on its card.
public enum ClipLook {
    /// Whether text reads as code, so its card sets it in a monospaced box: several lines with
    /// braces, semicolons or arrows, or lines that start indented.
    public static func isCode(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else {
            return text.contains("=>") || (text.hasSuffix(";") && text.contains("("))
        }
        let marked = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix("{") || trimmed.hasSuffix("}") || trimmed.hasSuffix(";")
                || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || line.hasPrefix("    ") || line.hasPrefix("\t")
        }
        return Double(marked.count) / Double(lines.count) >= 0.4
    }
}

// MARK: Layout

extension WindowLayout {
    /// The list column beside a detail.
    public static let masterWidth: Double = 300

    /// Whether a page `width` wide shows its list and detail side by side.
    public static func masterDetail(width: Double) -> Bool { width >= 760 }
}
