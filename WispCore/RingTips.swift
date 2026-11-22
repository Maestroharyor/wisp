import Foundation

/// The "Try the ring" checklist in Settings: the ring's gestures, ticked off as they're used.
public struct RingTips: Codable, Equatable, Sendable {
    public enum Step: String, CaseIterable, Codable, Sendable, Identifiable {
        case open
        case windows
        case search
        case number
        case convert

        public var id: Self { self }

        public var title: String {
            switch self {
            case .open: "Open the ring with its shortcut or mouse button"
            case .windows: "Point at an app on the ring that has a few windows open"
            case .search: "Type to search apps and actions"
            case .number: "Press a number to pick a segment"
            case .convert: "Drag a file, press the ring shortcut and drop it on a format"
            }
        }
    }

    public private(set) var done: Set<Step> = []

    public init() {}

    public var isComplete: Bool { done.count == Step.allCases.count }

    /// The first step not yet tried.
    public var next: Step? { Step.allCases.first { !done.contains($0) } }

    /// True when this marked something new, so callers only save on a change.
    @discardableResult
    public mutating func mark(_ step: Step) -> Bool {
        done.insert(step).inserted
    }

    public mutating func reset() { done = [] }

    private enum CodingKeys: String, CodingKey { case done }

    /// Steps this version doesn't know are dropped rather than failing the whole list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let names = ((try? container.decodeIfPresent([String].self, forKey: .done)) ?? nil) ?? []
        done = Set(names.compactMap(Step.init(rawValue:)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Step.allCases.filter(done.contains).map(\.rawValue), forKey: .done)
    }
}
