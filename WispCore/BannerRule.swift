import Foundation

/// Which macOS notification banners Wisp may close once it shows its own card. A banner with
/// Accept or Decline (an AirDrop request, an incoming call) is a question only the banner can
/// answer, so it stays whatever else arrives.
public enum BannerRule {
    /// The answers that keep a banner on screen.
    private static let answers: Set<String> = ["Accept", "Decline"]

    /// An Accessibility action's title. Notification Center names custom actions
    /// "Name:Accept\nTarget:0x0\nSelector:(null)"; standard ones are plain ("AXPress").
    public static func title(of action: String) -> String {
        let firstLine = action.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? action
        let prefix = "Name:"
        guard firstLine.hasPrefix(prefix) else { return firstLine }
        return String(firstLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    /// Whether a banner offering these actions asks something only it can answer.
    public static func keepsBanner(actions: [String]) -> Bool {
        actions.contains { answers.contains(title(of: $0)) }
    }

    /// The action that closes a banner offering these actions, or nil when it has none or must
    /// stay.
    public static func closeAction(in actions: [String]) -> String? {
        guard !keepsBanner(actions: actions) else { return nil }
        return actions.first { title(of: $0).contains("Close") }
    }
}
