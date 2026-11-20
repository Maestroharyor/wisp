import Foundation

/// What stands for a sender that has no icon of its own.
public enum SenderIcon: Sendable, Equatable {
    /// Another app's icon.
    case app(String)
    /// AirDrop's own icon, as the share menu draws it (falling back to AirDrop.app's).
    case airDrop
}

/// How Wisp shows a notification from a system service that has no app of its own.
public struct SenderIdentity: Sendable, Equatable {
    /// The name the card shows instead of the raw bundle identifier.
    public let displayName: String
    public let icon: SenderIcon
    /// An app to open when the card is clicked and there's no folder to open instead.
    public let appID: String
    /// A folder in the home folder that clicking the card opens, when there's no app to open.
    public let homeFolder: String?
    /// The system banner carries buttons Wisp's card doesn't have, so it must stay on screen.
    public let keepsSystemBanner: Bool
}

/// Background services that post notifications under their own bundle identifier. They have
/// no app bundle, so looking up their name or icon the usual way finds nothing.
public enum SystemSenders {
    /// AirDrop.app inside Finder, the one bundle that carries AirDrop's icon.
    public static let airDropApp = "com.apple.finder.Open-AirDrop"

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
            displayName: "AirDrop", icon: .airDrop, appID: SystemSenders.airDropApp, homeFolder: "Downloads",
            keepsSystemBanner: true)
    ]
}
