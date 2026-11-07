import Darwin
import Foundation

/// Where in a terminal the agent runs, from a fixed list of environment variables plus the
/// agent's tty, so Wisp can bring forward the exact pane or tab rather than just the app.
/// Nothing else from the environment is read.
public struct TerminalContext: Equatable, Sendable {
    /// `$TMUX`: the server's socket path, its pid and the session index, comma separated.
    public var tmux: String?
    public var tmuxPane: String?
    /// `$ITERM_SESSION_ID`: `w0t1p0:<session GUID>`.
    public var iTermSessionID: String?
    /// `$TERM_SESSION_ID`, set by Terminal.app (and by iTerm2 to the same value as its own).
    public var termSessionID: String?
    public var kittyWindowID: String?
    public var weztermPane: String?
    public var termProgram: String?
    /// The agent's controlling terminal device, such as `/dev/ttys003`.
    public var tty: String?

    /// The envelope key (see `docs/agent-protocol.md`). `terminal` already holds the app's
    /// bundle id as a string, which older Wisps read, so the context gets its own key.
    public static let envelopeKey = "terminalContext"
    static let ttyKey = "tty"
    /// Anything longer isn't one of these values; it's dropped rather than trimmed.
    static let maxLength = 512

    // Computed: key paths aren't Sendable, so they can't sit in a static constant.
    private static var variables: [(name: String, path: WritableKeyPath<TerminalContext, String?>)] {
        [
            ("TMUX", \.tmux), ("TMUX_PANE", \.tmuxPane), ("ITERM_SESSION_ID", \.iTermSessionID),
            ("TERM_SESSION_ID", \.termSessionID), ("KITTY_WINDOW_ID", \.kittyWindowID),
            ("WEZTERM_PANE", \.weztermPane), ("TERM_PROGRAM", \.termProgram),
        ]
    }

    public init(environment: [String: String], tty: String?) {
        for variable in Self.variables {
            self[keyPath: variable.path] = Self.clean(environment[variable.name])
        }
        self.tty = Self.clean(tty)
    }

    public var isEmpty: Bool { self == TerminalContext(environment: [:], tty: nil) }

    /// The tmux server's socket, for `tmux -S`.
    public var tmuxSocket: String? {
        guard let socket = tmux?.split(separator: ",", omittingEmptySubsequences: false).first, !socket.isEmpty
        else { return nil }
        return String(socket)
    }

    /// The session's GUID, which iTerm2's AppleScript calls the session's `id`.
    public var iTermSessionGUID: String? {
        guard let id = iTermSessionID, let colon = id.firstIndex(of: ":") else { return nil }
        let guid = id[id.index(after: colon)...]
        return guid.isEmpty ? nil : String(guid)
    }

    var json: JSONValue {
        var fields: [String: JSONValue] = [:]
        for variable in Self.variables {
            if let value = self[keyPath: variable.path] { fields[variable.name] = .string(value) }
        }
        if let tty { fields[Self.ttyKey] = .string(tty) }
        return .object(fields)
    }

    /// Unknown keys and values that aren't strings are ignored, so the helper can add keys.
    init?(json: JSONValue?) {
        guard case .object(let fields) = json else { return nil }
        var environment: [String: String] = [:]
        for (key, value) in fields {
            if let text = value.stringValue { environment[key] = text }
        }
        self.init(environment: environment, tty: environment[Self.ttyKey])
        if isEmpty { return nil }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= maxLength else { return nil }
        return value
    }

    /// `/dev/<name>` for a device name from `devname`; nil for none (`??`).
    public static func ttyPath(deviceName: String?) -> String? {
        guard let deviceName, !deviceName.isEmpty, deviceName != "??", !deviceName.contains("/") else { return nil }
        return "/dev/" + deviceName
    }

    /// The controlling terminal of `pid`, from the process table.
    public static func controllingTTY(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var entry = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &entry, &size, nil, 0) == 0, size > 0, entry.kp_proc.p_pid == pid
        else { return nil }
        let device = entry.kp_eproc.e_tdev
        // NODEV: no controlling terminal.
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        return ttyPath(deviceName: String(cString: name))
    }
}
