import Foundation

/// Scores how well typed text finds a name, the way a launcher should: the start of the name
/// first, then the start of a word ("code" in "Visual Studio Code"), then initials ("vsc",
/// "ss" for "SoundSource"), then text anywhere, then the letters in order. Within a tier the
/// shorter name wins. Case and accents are ignored.
public enum FuzzyMatch {
    private enum Tier: Int {
        case subsequence = 1
        case substring
        case initials
        case wordPrefix
        case prefix
    }

    /// Higher is better; nil when the text doesn't find the name at all.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let typed = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !typed.isEmpty else { return nil }
        let name = fold(candidate)
        guard let tier = tier(of: typed, in: name, words: words(of: candidate)) else { return nil }
        // Names are far shorter than this, so a tier always outranks the one below it.
        return tier.rawValue * 10_000 - name.count
    }

    private static func tier(of typed: String, in name: String, words: [String]) -> Tier? {
        if name.hasPrefix(typed) { return .prefix }
        if words.contains(where: { $0.hasPrefix(typed) }) { return .wordPrefix }
        if words.count > 1, String(words.compactMap(\.first)).hasPrefix(typed) { return .initials }
        if name.contains(typed) { return .substring }
        if isSubsequence(typed.filter { !$0.isWhitespace }, of: name) { return .subsequence }
        return nil
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Words split at spaces and punctuation, and at a capital after a small letter
    /// ("SoundSource" is "sound" and "source"), folded.
    static func words(of name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in name {
            if !character.isLetter && !character.isNumber {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                if character.isUppercase, let previous, previous.isLowercase, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words.map(fold)
    }

    private static func isSubsequence(_ typed: String, of name: String) -> Bool {
        var remaining = typed[...]
        for character in name where remaining.first == character {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}

/// An app on the Mac, as the ring's search lists it.
public struct InstalledApp: Equatable, Sendable {
    public let name: String
    public let bundleID: String
    public let path: String

    public init(name: String, bundleID: String, path: String) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }
}

/// Typing on the open ring: the ring's own actions and the Mac's apps, best match first.
public enum RingSearch {
    public static let limit = 6

    public struct Result: Equatable, Sendable, Identifiable {
        public let id: String
        public let action: RingAction
        public let score: Int
    }

    public static func results(_ query: String, ring: [RingAction], apps: [InstalledApp]) -> [Result] {
        var seen = Set<String>()
        var results: [Result] = []
        for action in ring where action.kind != .none {
            let key = action.kind == .app ? "app:" + (action.value ?? "") : "\(action.kind):\(action.value ?? "")"
            guard !seen.contains(key), let score = FuzzyMatch.score(query, in: action.title) else { continue }
            seen.insert(key)
            // What's already on the ring wins a tie with an app of the same name.
            results.append(Result(id: key, action: action, score: score + 1))
        }
        for app in apps {
            let key = "app:" + app.bundleID
            guard !seen.contains(key), let score = FuzzyMatch.score(query, in: app.name) else { continue }
            seen.insert(key)
            results.append(
                Result(id: key, action: RingAction(.app, value: app.bundleID, label: app.name), score: score))
        }
        return Array(results.sorted { ($0.score, $1.action.title) > ($1.score, $0.action.title) }.prefix(limit))
    }
}
