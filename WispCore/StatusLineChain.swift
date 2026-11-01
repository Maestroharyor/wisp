import Foundation

/// What the terminal bar shows once Claude Code is connected.
public enum TerminalBarMode: String, CaseIterable, Sendable {
    /// Wisp's bar. A bar the user had is kept inside the command and comes back with `off`.
    case wisp
    /// The user's own bar, run by the helper so Wisp still gets the data. Prints nothing
    /// when there's no bar of their own.
    case listen
    /// Claude Code's statusLine as it was before Wisp.
    case off
}

/// Who owns Claude Code's statusLine.
public enum StatusLineState: Equatable, Sendable {
    case none
    /// Wisp's bar; `saved` is the user's command it displaced.
    case wisp(saved: String?)
    /// The helper listens and runs `original` (nil: nothing to run).
    case listening(original: String?)
    /// Someone else's command.
    case foreign(String)

    /// The user's own command, wherever it is kept.
    public var userCommand: String? {
        switch self {
        case .none: nil
        case .wisp(let saved): saved
        case .listening(let original): original
        case .foreign(let command): command
        }
    }
}

/// Edits the `statusLine` block of Claude Code's settings.json. The user's own command is
/// kept inside Wisp's (`--saved` or `--chain`), so turning the bar off puts it back exactly,
/// with no other state to lose. Other keys (`padding`, `refreshInterval`) are never touched.
public enum StatusLineChain {
    public static let subcommand = "statusline"
    static let chainFlag = "--chain"
    static let savedFlag = "--saved"

    public static func state(in settings: Data) throws -> StatusLineState {
        state(in: try object(settings))
    }

    public static func install(_ mode: TerminalBarMode, into settings: Data, helper: String) throws -> Data {
        var root = try object(settings)
        let user = state(in: root).userCommand
        let base = HookInstaller.quote(helper) + " " + subcommand
        let command: String?
        switch mode {
        case .wisp: command = user.map { base + " \(savedFlag) " + HookInstaller.quote($0) } ?? base
        case .listen: command = user.map { base + " \(chainFlag) " + HookInstaller.quote($0) } ?? base + " --quiet"
        case .off: command = user
        }
        guard let command else {
            root["statusLine"] = nil
            return try encode(root)
        }
        var block: [String: JSONValue] = ["type": .string("command")]
        if case .object(let existing) = root["statusLine"] { block = existing }
        block["command"] = .string(command)
        root["statusLine"] = .object(block)
        return try encode(root)
    }

    /// The settings with the user's own statusLine back, or none if they had none.
    public static func restore(from settings: Data) throws -> Data {
        try install(.off, into: settings, helper: "")
    }

    /// Parses one of Wisp's commands back into its parts. A command from another copy of
    /// Wisp counts as Wisp's, so its saved bar is carried over rather than wrapped twice.
    static func state(ofCommand command: String) -> StatusLineState {
        guard let range = command.range(of: "\(HookInstaller.helperName)' \(subcommand)") else {
            return .foreign(command)
        }
        let rest = command[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if let saved = argument(after: savedFlag, in: rest) { return .wisp(saved: saved) }
        if let chained = argument(after: chainFlag, in: rest) { return .listening(original: chained) }
        return rest.hasPrefix("--quiet") ? .listening(original: nil) : .wisp(saved: nil)
    }

    private static func argument(after flag: String, in rest: String) -> String? {
        guard rest.hasPrefix(flag + " ") else { return nil }
        return HookInstaller.unquote(String(rest.dropFirst(flag.count + 1)))
    }

    private static func state(in root: [String: JSONValue]) -> StatusLineState {
        guard let command = root["statusLine"]?["command"]?.stringValue, !command.isEmpty else { return .none }
        return state(ofCommand: command)
    }

    private static func object(_ data: Data) throws -> [String: JSONValue] {
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard case .object(let root) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw HookInstaller.Failure.notAnObject
        }
        return root
    }

    private static func encode(_ root: [String: JSONValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(root))
    }
}
