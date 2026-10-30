import Foundation

/// What the helper adds to each hook call before forwarding it: which agent sent it and
/// which app it runs in, so Wisp can bring that app forward later.
public enum AgentTerminal {
    /// macOS sets `__CFBundleIdentifier` for processes started from an app, and terminals
    /// pass it to their shells. `TERM_PROGRAM` covers the rest.
    public static func bundleID(cfBundleIdentifier: String?, termProgram: String?) -> String? {
        if let id = cfBundleIdentifier, !id.isEmpty { return id }
        switch termProgram {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        case "vscode": return "com.microsoft.VSCode"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        case "WezTerm": return "com.github.wez.wezterm"
        default: return nil
        }
    }

    /// The hook's JSON with `wisp_source` and `wisp_terminal` added. Input that is not a
    /// JSON object passes through unchanged.
    public static func tag(_ input: Data, source: AgentSource, terminal: String?) -> Data {
        guard case .object(var fields) = try? JSONDecoder().decode(JSONValue.self, from: input) else { return input }
        fields["wisp_source"] = .string(source.rawValue)
        if let terminal { fields["wisp_terminal"] = .string(terminal) }
        return (try? JSONEncoder().encode(JSONValue.object(fields))) ?? input
    }
}
