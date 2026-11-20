import Foundation

/// One window of an app, as Accessibility reports it.
public struct WindowSummary: Equatable, Sendable {
    public let title: String?
    public let isMinimised: Bool

    public init(title: String?, isMinimised: Bool) {
        self.title = title
        self.isMinimised = isMinimised
    }
}

/// An app segment's sub-ring of its windows, frontmost first, so one can be brought forward
/// directly. A lone window needs no sub-ring; past the limit the last entry counts the rest.
public enum AppWindows {
    /// Six fan out over half the ring; more would wrap round it.
    public static let limit = 6
    public static let windowSymbol = "macwindow"
    public static let minimisedSymbol = "arrow.down.right.and.arrow.up.left"
    private static let prefix = "window:"

    /// Which window a choice stands for: its place in the list when the ring opened, and its
    /// title, so it's still found if windows moved in front of it meanwhile.
    public struct Target: Equatable, Sendable {
        public let index: Int
        public let title: String?

        public init(index: Int, title: String?) {
            self.index = index
            self.title = title
        }
    }

    public static func choices(appName: String, windows: [WindowSummary]) -> [RingChoice] {
        guard windows.count > 1 else { return [] }
        let shown = windows.count > limit ? limit - 1 : windows.count
        var choices = windows.prefix(shown).enumerated().map { index, window in
            let name = title(of: window) ?? "\(appName) window \(index + 1)"
            return RingChoice(
                id: prefix + "\(index):" + (title(of: window) ?? ""),
                title: window.isMinimised ? "\(name) (minimised)" : name,
                icon: .symbol(window.isMinimised ? minimisedSymbol : windowSymbol))
        }
        if windows.count > shown {
            choices.append(RingChoice(id: "windows:more", title: "\(windows.count - shown) more", symbol: "ellipsis"))
        }
        return choices
    }

    public static func target(of choice: RingChoice) -> Target? {
        guard choice.id.hasPrefix(prefix) else { return nil }
        let rest = choice.id.dropFirst(prefix.count)
        guard let colon = rest.firstIndex(of: ":"), let index = Int(rest[..<colon]) else { return nil }
        let title = String(rest[rest.index(after: colon)...])
        return Target(index: index, title: title.isEmpty ? nil : title)
    }

    /// The window a target now is: the one with its title (the nearest to its old place if
    /// several share it). An untitled window is whatever untitled one is at its old place; a
    /// titled one that's gone matches nothing, rather than raising some other window.
    public static func match(_ target: Target, in windows: [WindowSummary]) -> Int? {
        if let title = target.title {
            let same = windows.indices.filter { Self.title(of: windows[$0]) == title }
            return same.min(by: { abs($0 - target.index) < abs($1 - target.index) })
        }
        guard windows.indices.contains(target.index), title(of: windows[target.index]) == nil else { return nil }
        return target.index
    }

    private static func title(of window: WindowSummary) -> String? {
        guard let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
    }
}
