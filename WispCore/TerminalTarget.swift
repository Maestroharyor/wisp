import Foundation

/// How to bring a session's terminal forward, most precise first: its tmux pane, then the
/// host terminal's tab or session, then the app itself, then its folder in Terminal.
public struct TerminalTarget: Equatable, Sendable {
    public struct TmuxPane: Equatable, Sendable {
        /// From `$TMUX`; nil uses tmux's default server.
        public let socket: String?
        public let pane: String

        public init(socket: String?, pane: String) {
            self.socket = socket
            self.pane = pane
        }

        /// A tmux command line aimed at this pane's server.
        public func arguments(_ command: [String]) -> [String] {
            (socket.map { ["-S", $0] } ?? []) + command
        }
    }

    /// A tab, session or pane in the host terminal.
    public enum Tab: Equatable, Sendable {
        case iTermSession(String)
        case iTermTTY(String)
        case terminalApp(String)
        case ghostty(String)
        case wezterm(pane: String)
    }

    public enum Strategy: Equatable, Sendable {
        case tmuxPane
        case tab
        case activateApp
        case openFolder
        case nothing
    }

    public let tmux: TmuxPane?
    public let tab: Tab?
    public let bundleID: String?
    public let folder: String?
    /// Kept to rebuild the tab when the tmux step turns out not to apply.
    private let context: TerminalContext?

    public static let iTerm = "com.googlecode.iterm2"
    public static let terminalApp = "com.apple.Terminal"
    public static let ghostty = "com.mitchellh.ghostty"
    public static let wezterm = "com.github.wez.wezterm"
    /// Editors whose own terminals inherit TMUX when the editor was started from a tmux shell.
    /// A deny list rather than a list of terminals, so a terminal Wisp doesn't know keeps the
    /// tmux step; the pane's tty is checked against the agent's either way.
    static let editors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "com.google.antigravity", "dev.zed.Zed", "com.apple.dt.Xcode",
    ]

    static func isEditor(_ bundleID: String) -> Bool {
        editors.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.")
    }

    public init(context: TerminalContext?, bundleID: String?, cwd: String) {
        let bundleID = bundleID ?? Self.inferredBundle(context)
        self.bundleID = bundleID
        self.folder = cwd.isEmpty ? nil : cwd
        self.context = context
        // An editor started from a tmux shell passes TMUX on to its own terminals, which
        // aren't in tmux.
        let hostCanRunTmux = !(bundleID.map(Self.isEditor) ?? false)
        if hostCanRunTmux, let context, let pane = context.tmuxPane, Self.isTmuxPane(pane) {
            tmux = TmuxPane(socket: context.tmuxSocket, pane: pane)
            // Inside tmux the tty is the pane's and host ids are whatever the server started
            // with, so the tab is found later from the tmux client's tty.
            tab = nil
        } else {
            tmux = nil
            tab = Self.tab(bundleID: bundleID, context: context, tty: context?.tty)
        }
    }

    /// The target once tmux has said which client shows the pane: that client's tty is the
    /// host terminal's tab.
    public func withClientTTY(_ tty: String) -> TerminalTarget {
        TerminalTarget(tmux: tmux, tab: Self.tab(bundleID: bundleID, context: nil, tty: tty), copying: self)
    }

    /// The target when the tmux pane isn't the agent's: its own tty and ids name the tab.
    public func withoutTmux() -> TerminalTarget {
        TerminalTarget(
            tmux: nil, tab: Self.tab(bundleID: bundleID, context: context, tty: context?.tty), copying: self)
    }

    /// Whether tmux's pane is the agent's terminal. A shell started from tmux keeps TMUX and
    /// TMUX_PANE, but its tty is its own. Without the agent's tty the pane is trusted.
    public func paneMatches(paneTTY: String) -> Bool {
        guard let tty = context?.tty else { return true }
        return tty == paneTTY
    }

    private init(tmux: TmuxPane?, tab: Tab?, copying other: TerminalTarget) {
        self.tmux = tmux
        self.tab = tab
        self.bundleID = other.bundleID
        self.folder = other.folder
        self.context = other.context
    }

    /// The most precise way this target can be reached.
    public var strategy: Strategy {
        if tmux != nil { return .tmuxPane }
        if tab != nil { return .tab }
        if bundleID != nil { return .activateApp }
        return folder != nil ? .openFolder : .nothing
    }

    private static func tab(bundleID: String?, context: TerminalContext?, tty: String?) -> Tab? {
        switch bundleID {
        case iTerm:
            if let guid = context?.iTermSessionGUID { return .iTermSession(guid) }
            return tty.map(Tab.iTermTTY)
        case terminalApp: return tty.map(Tab.terminalApp)
        case ghostty: return tty.map(Tab.ghostty)
        case wezterm:
            guard let pane = context?.weztermPane, !pane.isEmpty, pane.allSatisfy(\.isASCIIDigit) else { return nil }
            return .wezterm(pane: pane)
        default: return nil
        }
    }

    /// For a helper that couldn't name the app (no `__CFBundleIdentifier`).
    private static func inferredBundle(_ context: TerminalContext?) -> String? {
        guard let context else { return nil }
        if context.iTermSessionID != nil { return iTerm }
        if context.weztermPane != nil { return wezterm }
        return AgentTerminal.bundleID(cfBundleIdentifier: nil, termProgram: context.termProgram)
    }

    /// tmux pane ids are `%` and a number; anything else could read as a tmux option.
    static func isTmuxPane(_ pane: String) -> Bool {
        pane.hasPrefix("%") && pane.count > 1 && pane.dropFirst().allSatisfy(\.isASCIIDigit)
    }
}

/// Picks the tmux client to show a pane in, from
/// `tmux list-clients -F '#{client_tty}\t#{session_name}\t#{client_activity}'`.
public enum TmuxClients {
    public static let format = "#{client_tty}\t#{session_name}\t#{client_activity}"
    /// For `display-message -p -t <pane>`: the pane's tty, then its session. The tty goes
    /// first because a session name can hold a tab.
    public static let paneFormat = "#{pane_tty}\t#{session_name}"

    public struct PaneInfo: Equatable, Sendable {
        public let session: String
        public let tty: String
    }

    public static func paneInfo(_ output: String) -> PaneInfo? {
        let line = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 2, fields[0].hasPrefix("/dev/"), !fields[1].isEmpty else { return nil }
        return PaneInfo(session: fields[1], tty: fields[0])
    }

    public struct Choice: Equatable, Sendable {
        public let tty: String
        /// No client shows the pane's session, so this one has to switch to it.
        public let switchTo: Bool
    }

    /// The most recently used client on `session`, otherwise the most recently used one.
    public static func pick(listOutput: String, session: String) -> Choice? {
        let clients = listOutput.split(whereSeparator: \.isNewline).compactMap { line -> (String, String, Int)? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, fields[0].hasPrefix("/dev/") else { return nil }
            return (fields[0], fields[1], Int(fields[2]) ?? 0)
        }
        let byActivity = clients.sorted { $0.2 > $1.2 }
        if let match = byActivity.first(where: { $0.1 == session }) { return Choice(tty: match.0, switchTo: false) }
        return byActivity.first.map { Choice(tty: $0.0, switchTo: true) }
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

/// AppleScript that selects one tab and brings its window forward. Each returns `found`
/// when it found the tab and nothing otherwise, so the caller can fall back.
public enum TerminalScript {
    public static let found = "found"

    public static func iTerm(sessionID: String) -> String {
        iTermSession(matching: "id of s is \(quoted(sessionID))")
    }

    public static func iTerm(tty: String) -> String {
        iTermSession(matching: "tty of s is \(quoted(tty))")
    }

    private static func iTermSession(matching condition: String) -> String {
        """
        tell application id "\(TerminalTarget.iTerm)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if \(condition) then
                            select w
                            select t
                            select s
                            activate
                            return "\(found)"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    public static func terminalApp(tty: String) -> String {
        """
        tell application id "\(TerminalTarget.terminalApp)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is \(quoted(tty)) then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "\(found)"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    /// Ghostty 1.3 and later; `macos-applescript = false` turns its dictionary off.
    public static func ghostty(tty: String) -> String {
        """
        tell application id "\(TerminalTarget.ghostty)"
            repeat with t in terminals
                if tty of t is \(quoted(tty)) then
                    focus t
                    activate
                    return "\(found)"
                end if
            end repeat
        end tell
        return ""
        """
    }

    /// An AppleScript string literal.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Where to look for a terminal's command line tool (`tmux`, `wezterm`): the login shell's
/// PATH first, as the user's terminal sees it, then the usual install folders.
public enum TerminalTools {
    public static func candidates(_ name: String, path: String?, home: String) -> [String] {
        let entries = (path ?? "").split(separator: ":").map { entry -> String in
            var entry = String(entry)
            if entry.hasPrefix("~/") { entry = home + entry.dropFirst() }
            if entry.hasPrefix("$HOME/") { entry = home + entry.dropFirst(5) }
            return entry
        }
        let usual = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin"]
        var seen = Set<String>()
        return (entries + usual).filter { $0.hasPrefix("/") && seen.insert($0).inserted }.map { "\($0)/\(name)" }
    }
}
