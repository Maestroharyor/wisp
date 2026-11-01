import CoreGraphics

/// How wide a widget sits on Home.
public enum WidgetSize: String, Codable, Sendable, CaseIterable {
    /// A size this version doesn't know (saved by a newer Wisp) reads as large, so the rest
    /// of the layout and the profiles holding it still load.
    public init(from decoder: Decoder) throws {
        self = WidgetSize(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .large
    }

    case small
    case medium
    case large
    /// The whole shelf, for a widget that is the profile's only one (Agents in Code).
    case wide

    public var width: CGFloat {
        switch self {
        case .small: 180
        case .medium: 240
        case .large: 330
        case .wide: 560
        }
    }

    /// The size the resize button switches to, among `sizes` (a widget's allowed sizes).
    public func next(in sizes: [WidgetSize]) -> WidgetSize {
        guard let index = sizes.firstIndex(of: self) else { return sizes.first ?? self }
        return sizes[(index + 1) % sizes.count]
    }

    /// Sizes every widget can take. Only widgets built for it also go `wide`.
    public static let standard: [WidgetSize] = [.small, .medium, .large]
}

/// The widgets on Home: up to four, in order, each with a size.
public struct HomeLayout: Codable, Sendable, Equatable {
    public struct Slot: Codable, Sendable, Equatable {
        public var id: String
        public var size: WidgetSize

        public init(id: String, size: WidgetSize) {
            self.id = id
            self.size = size
        }
    }

    public static let maxSlots = 4
    /// Space for the divider between widgets: padding either side of a hairline.
    public static let dividerSpacing: CGFloat = 25

    public private(set) var slots: [Slot]

    public init(slots: [Slot] = []) {
        self.slots = Array(slots.prefix(Self.maxSlots))
    }

    public var ids: [String] { slots.map(\.id) }
    public var isFull: Bool { slots.count >= Self.maxSlots }

    public func contains(_ id: String) -> Bool { slots.contains { $0.id == id } }

    /// Total width of the row, dividers included.
    public var contentWidth: CGFloat { Self.contentWidth(of: slots.map(\.size)) }

    /// Width of any row of widgets with hairline dividers between them.
    public static func contentWidth(of sizes: [WidgetSize]) -> CGFloat {
        sizes.reduce(0) { $0 + $1.width } + CGFloat(max(sizes.count - 1, 0)) * dividerSpacing
    }

    /// Returns false when Home is full or the widget is already there.
    @discardableResult
    public mutating func add(_ id: String, size: WidgetSize) -> Bool {
        guard !isFull, !contains(id) else { return false }
        slots.append(Slot(id: id, size: size))
        return true
    }

    public mutating func remove(_ id: String) {
        slots.removeAll { $0.id == id }
    }

    /// Moves `id` to sit just before `target`.
    public mutating func move(_ id: String, before target: String) {
        guard id != target, let from = slots.firstIndex(where: { $0.id == id }) else { return }
        let slot = slots.remove(at: from)
        let to = slots.firstIndex { $0.id == target } ?? slots.count
        slots.insert(slot, at: to)
    }

    public mutating func resize(_ id: String, to size: WidgetSize) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        slots[index].size = size
    }
}

/// A fixed-size rolling window of samples, oldest first, for small charts.
public struct SampleHistory: Sendable, Equatable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public var latest: Double? { values.last }

    public mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
}
