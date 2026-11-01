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
        // Only the agents' status bars; a bar opens that session's details.
        Profile(name: "Code", home: layout(("agents", .wide)), defaultPage: "home", surface: "tinted"),
        Profile(name: "Music", home: layout(("nowPlaying", .large)), defaultPage: "media", surface: "tinted"),
        Profile(
            name: "Stats", home: layout(("systemStats", .medium), ("timer", .small), ("dayProgress", .medium)),
            defaultPage: "home", surface: "black"),
        Profile(
            name: "Meeting", home: layout(("mirror", .small), ("calendar", .medium), ("worldClocks", .small)),
            defaultPage: "home", surface: "black"),
    ]

    /// Bumped when the built-ins change in a way saved profiles should follow.
    public static let builtInsVersion = 4

    /// Saved profiles brought up to the current built-ins, once per version. Only a profile
    /// still exactly as Wisp first made it is changed; one the user edited is theirs. New
    /// built-ins are added once, so deleting one later sticks.
    public static func upgrade(_ profiles: [Profile], from version: Int) -> [Profile] {
        var result = profiles
        // Version 3 changed Code but a Home still on the old layout copied it back, so 4 repeats it.
        if version < 4 {
            let earlierCodes = [
                layout(("agents", .medium), ("systemStats", .medium), ("timer", .small)), layout(("agents", .large)),
            ].map { Profile(name: "Code", home: $0, defaultPage: "home", surface: "tinted") }
            if let index = result.firstIndex(where: earlierCodes.contains),
                let code = builtIns.first(where: { $0.name == "Code" })
            {
                result[index] = code
            }
        }
        if version < 2 {
            if !result.contains(where: { $0.name == "Stats" }),
                let stats = builtIns.first(where: { $0.name == "Stats" })
            {
                result.append(stats)
            }
        }
        return result
    }

    /// The Home on screen after `upgrade`: it follows its profile's new layout only while
    /// it's still the profile's old one, so the user's own Home edits are kept.
    public static func upgradedHome(
        _ current: HomeLayout, profile name: String, before: [Profile], after: [Profile]
    ) -> HomeLayout {
        guard let old = before.first(where: { $0.name == name }), let new = after.first(where: { $0.name == name }),
            old.home == current
        else { return current }
        return new.home
    }

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
