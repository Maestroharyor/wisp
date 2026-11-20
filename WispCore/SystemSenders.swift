import Foundation

/// How Wisp shows a notification from a system service that has no app of its own.
public struct SenderIdentity: Sendable, Equatable {
    /// The name the card shows instead of the raw bundle identifier.
    public let displayName: String
    /// An app whose icon stands for the service.
    public let iconAppID: String
    /// A folder in the home folder that clicking the card opens, when there's no app to open.
    public let homeFolder: String?
    /// The system banner carries buttons Wisp's card doesn't have, so it must stay on screen.
    public let keepsSystemBanner: Bool
}

/// Background services that post notifications under their own bundle identifier. They have
/// no app bundle, so looking up their name or icon the usual way finds nothing.
public enum SystemSenders {
    public static func identity(for appID: String) -> SenderIdentity? {
        known[appID]
    }

    /// Whether hiding system banners has to leave this sender's banner alone.
    public static func keepsSystemBanner(appID: String) -> Bool {
        identity(for: appID)?.keepsSystemBanner ?? false
    }

    // AirDrop's request banner has Accept and Decline; closing it would leave no way to accept.
    private static let known: [String: SenderIdentity] = [
        "com.apple.sharingd": SenderIdentity(
            displayName: "AirDrop", iconAppID: "com.apple.finder.Open-AirDrop", homeFolder: "Downloads",
            keepsSystemBanner: true)
    ]
}
