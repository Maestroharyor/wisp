/// Which displays show live activities (Now Playing, HUDs, timers).
public enum ActivityDisplayTarget: String, Sendable, CaseIterable {
    /// The display under the pointer, where the user is looking.
    case pointer
    /// The MacBook's own display.
    case builtIn
    /// Every display at once.
    case all

    /// Picks display identifiers. Falls back from the preferred display to the
    /// built-in one, then the main one, then the first available.
    public func displays(among ids: [String], builtIn: String?, pointer: String?, main: String?) -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let available = Set(ids)
        let preferred: [String?]
        switch self {
        case .all: return available
        case .pointer: preferred = [pointer, builtIn, main]
        case .builtIn: preferred = [builtIn, main]
        }
        let chosen = preferred.compactMap { $0 }.first(where: available.contains) ?? ids[0]
        return [chosen]
    }
}
