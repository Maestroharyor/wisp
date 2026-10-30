import Foundation

/// A saved shelf setup: which widgets sit on Home, which page opens first, and the surface.
public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    /// The Home widgets and their sizes.
    public var home: HomeLayout
    /// "home", "tray", "media" or "widgets".
    public var defaultPage: String
    /// A `SurfaceStyle` raw value.
    public var surface: String
    /// A saved look's name, applied with the profile; nil keeps the current look.
    public var look: String?

    public var id: String { name }

    public init(name: String, home: HomeLayout, defaultPage: String, surface: String, look: String? = nil) {
        self.name = name
        self.home = home
        self.defaultPage = defaultPage
        self.surface = surface
        self.look = look
    }

    public static let builtIns: [Profile] = [
        Profile(
            name: ContextEngineState.baseProfile, home: layout(("nowPlaying", .large), ("calendar", .medium)),
            defaultPage: "home", surface: "black"),
        Profile(
            name: "Work", home: layout(("calendar", .medium), ("dayProgress", .medium), ("pomodoro", .small)),
            defaultPage: "home", surface: "black"),
        Profile(
            name: "Code", home: layout(("agents", .medium), ("systemStats", .medium), ("timer", .small)),
            defaultPage: "home", surface: "tinted"),
        Profile(name: "Music", home: layout(("nowPlaying", .large)), defaultPage: "media", surface: "tinted"),
        Profile(
            name: "Meeting", home: layout(("mirror", .small), ("calendar", .medium), ("worldClocks", .small)),
            defaultPage: "home", surface: "black"),
    ]

    private static func layout(_ slots: (String, WidgetSize)...) -> HomeLayout {
        HomeLayout(slots: slots.map { HomeLayout.Slot(id: $0.0, size: $0.1) })
    }

    /// A trimmed name that doesn't clash: "Work" becomes "Work 2", "Work 3"…
    public static func uniqueName(_ proposed: String, existing: [String]) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? "Profile" : base
        guard existing.contains(name) else { return name }
        var number = 2
        while existing.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    /// Hyper+1 picks the first profile; digits past the list (or 0) pick nothing.
    public static func index(forDigit digit: Int, count: Int) -> Int? {
        (1...max(count, 1)).contains(digit) && digit <= count ? digit - 1 : nil
    }
}
