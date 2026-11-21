import Foundation

/// Which macOS notification banners Wisp may close once it shows its own card. A banner with
/// Accept or Decline (an AirDrop request, an incoming call) is a question only the banner can
/// answer, so it stays whatever else arrives.
public enum BannerRule {
    /// The answers that keep a banner on screen, matched at the start of a label ("Accept…").
    private static let answers = ["accept", "decline"]

    /// An Accessibility action's title. Notification Center names custom actions
    /// "Name:Accept\nTarget:0x0\nSelector:(null)"; standard ones are plain ("AXPress").
    public static func title(of action: String) -> String {
        let firstLine = action.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? action
        let prefix = "Name:"
        guard firstLine.hasPrefix(prefix) else { return firstLine }
        return String(firstLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    /// Whether a label (an action's name, or a button's title or description) is an answer.
    public static func isAnswer(_ label: String) -> Bool {
        let text = title(of: label).trimmingCharacters(in: .whitespaces).lowercased()
        return answers.contains { text.hasPrefix($0) }
    }

    /// Whether a banner whose parts carry these labels asks something only it can answer.
    /// "AirDrop" is a name macOS keeps in every language, so a request stays even where its
    /// buttons aren't called Accept and Decline.
    public static func keepsBanner(labels: [String]) -> Bool {
        labels.contains { isAnswer($0) || $0.localizedCaseInsensitiveContains("AirDrop") }
    }

    /// How much of a long body a banner shows before it cuts it off.
    private static let bodyStart = 40

    /// Whether a banner showing `texts` is the one for the card with this title and body, so
    /// Wisp never closes another app's banner. A banner with no text to read, or a card with
    /// nothing to compare, can't be told apart and counts as a match, as before.
    public static func shows(texts: [String], title: String, body: String) -> Bool {
        let shown = texts.map(folded).filter { !$0.isEmpty }
        let wanted = [folded(title), String(folded(body).prefix(bodyStart))].filter { !$0.isEmpty }
        guard !shown.isEmpty, !wanted.isEmpty else { return true }
        return wanted.contains { part in shown.contains { $0.contains(part) } }
    }

    private static func folded(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The action that closes a banner, or nil when it has none or `labels` say it must stay.
    public static func closeAction(in actions: [String], labels: [String] = []) -> String? {
        guard !keepsBanner(labels: actions + labels) else { return nil }
        return actions.first { title(of: $0).contains("Close") }
    }
}
