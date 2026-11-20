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
    public static func keepsBanner(labels: [String]) -> Bool {
        labels.contains(where: isAnswer)
    }

    /// The action that closes a banner, or nil when it has none or `labels` say it must stay.
    public static func closeAction(in actions: [String], labels: [String] = []) -> String? {
        guard !keepsBanner(labels: actions + labels) else { return nil }
        return actions.first { title(of: $0).contains("Close") }
    }
}
