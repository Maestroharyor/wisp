import Darwin
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

    /// What's at `link` now.
    public static func state(at link: URL, helper: URL) -> State {
        let manager = FileManager.default
        return state(
            exists: manager.fileExists(atPath: link.path),
            linkTarget: try? manager.destinationOfSymbolicLink(atPath: link.path), helper: helper.path)
    }

    public enum Problem: Error, Equatable {
        /// Something that isn't Wisp's is already called `wisp` there.
        case taken
    }

    /// Links `link` to `helper`, creating its folder and replacing only a link of Wisp's own.
    public static func install(at link: URL, helper: URL) throws {
        let manager = FileManager.default
        switch state(at: link, helper: helper) {
        case .installed: return
        case .foreign: throw Problem.taken
        case .otherApp, .notInstalled: break
        }
        let folder = link.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Made beside it, then renamed over it in one step, so a failure never leaves the
        // other copy's link gone with nothing in its place.
        let temporary = folder.appendingPathComponent(".wisp-\(UUID().uuidString)")
        try manager.createSymbolicLink(at: temporary, withDestinationURL: helper)
        guard rename(temporary.path, link.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Where to put `~/.local/bin` on PATH for the shell at `shell` (`$SHELL`): the file to
    /// edit and the line to add.
    public static func pathAdvice(shell: String?) -> (file: String, line: String) {
        switch URL(fileURLWithPath: shell ?? "").lastPathComponent {
        case "bash": ("~/.bash_profile", #"export PATH="$HOME/.local/bin:$PATH""#)
        case "fish": ("~/.config/fish/config.fish", "fish_add_path ~/.local/bin")
        default: ("~/.zshrc", #"export PATH="$HOME/.local/bin:$PATH""#)
        }
    }

    /// Removes `link` when it's Wisp's link to `helper`; anything else is left alone.
    public static func uninstall(at link: URL, helper: URL) throws {
        guard state(at: link, helper: helper) == .installed else { return }
        try FileManager.default.removeItem(at: link)
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
