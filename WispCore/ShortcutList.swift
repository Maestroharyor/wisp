import Foundation

/// Parses the output of `shortcuts list` and orders the user's favourites.
public enum ShortcutList {
    public static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Favourites in the user's order, without any that no longer exist.
    public static func favourites(_ favourites: [String], available: [String]) -> [String] {
        let names = Set(available)
        return favourites.filter(names.contains)
    }

    /// Names containing every word of `query`, ignoring case and accents; all of them when it's blank.
    public static func matching(_ names: [String], query: String) -> [String] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return names }
        return names.filter { name in
            words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
