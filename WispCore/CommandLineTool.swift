import Foundation

/// Decisions for installing `wisp` as a link to the helper in `~/.local/bin`, which needs
/// no admin rights. Wisp only ever replaces or removes a link of its own.
public enum CommandLineTool {
    public static let folder = ".local/bin"

    public enum State: Equatable, Sendable {
        case notInstalled
        case installed
        /// Wisp's link, pointing at another copy's helper (Wisp Dev, or an app since moved).
        case otherApp(String)
        /// Something else is called `wisp` there; it's left alone.
        case foreign
    }

    /// `exists` is whether anything (followed through links) is at the path; `linkTarget`
    /// is where it links to, or nil when it isn't a link.
    public static func state(exists: Bool, linkTarget: String?, helper: String) -> State {
        guard let linkTarget else { return exists ? .foreign : .notInstalled }
        if linkTarget == helper { return .installed }
        let isHelper =
            URL(fileURLWithPath: linkTarget).lastPathComponent == HookInstaller.helperName
            && linkTarget.contains(".app/Contents/MacOS/")
        return isHelper ? .otherApp(linkTarget) : .foreign
    }

    /// Whether `path` (a PATH value) has `~/.local/bin`.
    public static func isOnPath(_ path: String, home: String) -> Bool {
        let wanted = normalized("\(home)/\(folder)")
        return path.split(separator: ":").contains { entry in
            var entry = String(entry)
            if entry.hasPrefix("~/") { entry = home + entry.dropFirst() }
            if entry.hasPrefix("$HOME/") { entry = home + entry.dropFirst(5) }
            return normalized(entry) == wanted
        }
    }

    /// Run with `$SHELL -ilc` to read the user's PATH; the markers skip anything the shell's
    /// startup files print.
    public static let printPathCommand = #"printf '<<wisp-path>>%s<</wisp-path>>' "$PATH""#

    public static func path(fromShellOutput output: String) -> String? {
        guard let start = output.range(of: "<<wisp-path>>"),
            let end = output.range(of: "<</wisp-path>>", range: start.upperBound..<output.endIndex)
        else { return nil }
        return String(output[start.upperBound..<end.lowerBound])
    }

    private static func normalized(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
