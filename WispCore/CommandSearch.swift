import Foundation

/// Something the window's command bar can find or do.
public struct CommandItem: Equatable, Sendable, Identifiable {
    /// In the order the bar lists its groups.
    public enum Kind: Int, CaseIterable, Comparable, Sendable {
        case create
        case action
        case page
        case app
        case clip
        case note
        case reminder
        case event

        public var title: String {
            switch self {
            case .create: "Create"
            case .action: "Actions"
            case .page: "Pages"
            case .app: "Apps"
            case .clip: "Clipboard"
            case .note: "Notes"
            case .reminder: "Reminders"
            case .event: "Events"
            }
        }

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let kind: Kind
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    /// More text that finds the item (a note's body), ranked below a match in the title.
    public let keywords: String

    public init(kind: Kind, id: String, title: String, subtitle: String, symbol: String, keywords: String = "") {
        self.kind = kind
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.keywords = keywords
    }
}

public struct CommandGroup: Equatable, Sendable, Identifiable {
    public let kind: CommandItem.Kind
    public let items: [CommandItem]

    public var id: CommandItem.Kind { kind }
}

/// What the command bar lists for what's typed: a Quick add sentence to create first, then
/// matches grouped by kind, best first, a few of each.
public enum CommandSearch {
    public static let createID = "create"

    public static func cap(for kind: CommandItem.Kind) -> Int {
        switch kind {
        case .create: 1
        case .page: 4
        default: 5
        }
    }

    /// A blank query lists the actions and the first pages, as somewhere to start.
    public static func results(query: String, candidates: [CommandItem], now: Date, calendar: Calendar)
        -> [CommandGroup]
    {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            return group(candidates.filter { $0.kind == .action || $0.kind == .page })
        }
        var scored: [(item: CommandItem, score: Int)] = []
        if let create = create(typed, now: now, calendar: calendar) { scored.append((create, .max)) }
        for item in candidates {
            if let score = score(typed, item) { scored.append((item, score)) }
        }
        let ranked = scored.sorted { ($0.score, $1.item.title) > ($1.score, $0.item.title) }.map(\.item)
        return group(ranked)
    }

    /// The items in the order the bar shows them, for moving through with the arrow keys.
    public static func flat(_ groups: [CommandGroup]) -> [CommandItem] {
        groups.flatMap(\.items)
    }

    /// The highlighted row after an arrow key, wrapping at either end.
    public static func stepped(_ index: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + step) % count + count) % count
    }

    private static func score(_ typed: String, _ item: CommandItem) -> Int? {
        if let score = FuzzyMatch.score(typed, in: item.title) { return score }
        guard !item.keywords.isEmpty,
            FuzzyMatch.fold(item.keywords).contains(FuzzyMatch.fold(typed))
        else { return nil }
        // Below any match in a title.
        return 0
    }

    /// The Quick add request `typed` reads as, when it reads as one that can be made now.
    private static func create(_ typed: String, now: Date, calendar: Calendar) -> CommandItem? {
        guard let intent = QuickInputParser.parse(typed, now: now, calendar: calendar),
            QuickIntentCheck.problem(intent, now: now) == nil
        else { return nil }
        return CommandItem(
            kind: .create, id: createID, title: QuickIntentText.headline(intent),
            subtitle: QuickIntentText.detail(intent, now: now, calendar: calendar),
            symbol: QuickIntentText.symbol(intent))
    }

    private static func group(_ items: [CommandItem]) -> [CommandGroup] {
        CommandItem.Kind.allCases.compactMap { kind in
            let matching = items.filter { $0.kind == kind }.prefix(cap(for: kind))
            return matching.isEmpty ? nil : CommandGroup(kind: kind, items: Array(matching))
        }
    }
}
