import Foundation

/// Where Wisp keeps its files, so a development build ("Wisp Dev") never shares the clipboard
/// history or the agent socket with the installed app.
public enum AppSupport {
    public static let developmentSuffix = ".dev"

    /// "Wisp Dev" for a development build's bundle id, "Wisp" otherwise.
    public static func folderName(bundleID: String?) -> String {
        bundleID?.hasSuffix(developmentSuffix) == true ? "Wisp Dev" : "Wisp"
    }

    /// `~/Library/Application Support/<folder>/agents.sock`.
    public static func socketURL(home: URL, bundleID: String?) -> URL {
        home.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(folderName(bundleID: bundleID))
            .appendingPathComponent("agents.sock")
    }

    /// The app a helper lives in: `<App>.app/Contents/Helpers/<helper>` gives `<App>.app`.
    public static func appBundle(containingHelper helper: URL) -> URL {
        helper.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
