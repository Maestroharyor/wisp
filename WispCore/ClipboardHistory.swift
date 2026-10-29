import CoreGraphics
import Foundation

public enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text
    case link
    case image
    case color
}

public struct ClipItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: ClipKind
    /// Text, link or colour string. Nil for images.
    public var text: String?
    /// File name of a stored image, relative to the clipboard store folder.
    public var imageFile: String?
    public var imagePixelSize: CGSize?
    public var sourceApp: String?
    public var sourceBundleID: String?
    public var date: Date
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        text: String? = nil,
        imageFile: String? = nil,
        imagePixelSize: CGSize? = nil,
        sourceApp: String? = nil,
        sourceBundleID: String? = nil,
        date: Date,
        pinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.imagePixelSize = imagePixelSize
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.date = date
        self.pinned = pinned
    }

    /// Same content regardless of when or where it was copied.
    func isDuplicate(of other: ClipItem) -> Bool {
        kind == other.kind && kind != .image && text == other.text
    }
}

/// Newest-first clipboard history with de-duplication and a size cap. Pinned items
/// are never evicted.
public struct ClipboardHistory: Codable, Sendable, Equatable {
    public private(set) var items: [ClipItem] = []
    public var limit: Int

    public init(limit: Int = 200) {
        self.limit = limit
    }

    /// Inserts at the front. A duplicate moves to the front and keeps its pin.
    /// Returns items evicted by the cap so the owner can delete their files.
    @discardableResult
    public mutating func add(_ item: ClipItem) -> [ClipItem] {
        var item = item
        if let index = items.firstIndex(where: { $0.isDuplicate(of: item) }) {
            item.pinned = items[index].pinned
            item.id = items[index].id
            items.remove(at: index)
        }
        items.insert(item, at: 0)

        var evicted: [ClipItem] = []
        while items.count > limit, let index = items.lastIndex(where: { !$0.pinned }) {
            evicted.append(items.remove(at: index))
        }
        return evicted
    }

    @discardableResult
    public mutating func remove(id: UUID) -> ClipItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    public mutating func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
    }

    /// Removes everything except pinned items; returns what was removed.
    @discardableResult
    public mutating func clearUnpinned() -> [ClipItem] {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        return removed
    }

    /// Pinned first, then newest. `kind` nil means all kinds.
    public func filtered(kind: ClipKind?, query: String) -> [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = items.filter { item in
            (kind == nil || item.kind == kind)
                && (needle.isEmpty
                    || (item.text?.lowercased().contains(needle) ?? false)
                    || (item.sourceApp?.lowercased().contains(needle) ?? false))
        }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }
}

/// Classifies copied text.
public enum ClipClassifier {
    public static func kind(for text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if rgb(fromHex: trimmed) != nil { return .color }
        if isLink(trimmed) { return .link }
        return .text
    }

    public static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text) else { return false }
        if let scheme = url.scheme?.lowercased() {
            return ["http", "https"].contains(scheme) && url.host() != nil
        }
        return text.lowercased().hasPrefix("www.") && text.contains(".")
    }

    /// Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA` into 0...255 components.
    public static func rgb(fromHex text: String) -> (red: Int, green: Int, blue: Int)? {
        guard text.hasPrefix("#") else { return nil }
        var hex = String(text.dropFirst())
        guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(hex.prefix(6), radix: 16) else { return nil }
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }
}
