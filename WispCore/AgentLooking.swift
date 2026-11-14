import Foundation

/// Whether the user is already looking at a session's terminal, so its sound and Done card
/// would only repeat what's on screen. The app in front decides; where the terminal can say
/// which tab is selected (iTerm2 and Terminal, outside tmux), that tab must be the session's.
public enum AgentLooking {
    /// A read of the front terminal's selected tab, to compare with the session's tty.
    public struct Probe: Equatable, Sendable {
        public let app: String
        public let tty: String

        public init(app: String, tty: String) {
            self.app = app
            self.tty = tty
        }

        /// Reads the selected tab's tty, and nothing else, from the app in front.
        public var script: String {
            app == TerminalTarget.iTerm
                ? "tell application id \"\(app)\" to get tty of current session of current window"
                : "tell application id \"\(app)\" to get tty of selected tab of front window"
        }
    }

    /// `activeTTY` is the front tab's tty, nil when it can't be known; then the app is enough.
    public static func isLooking(frontmost: String?, sessionApp: String?, sessionTTY: String?, activeTTY: String?)
        -> Bool
    {
        guard let frontmost, let sessionApp, frontmost == sessionApp else { return false }
        guard let sessionTTY, let activeTTY else { return true }
        return name(of: sessionTTY) == name(of: activeTTY)
    }

    /// The tab read for a session, or nil when its tab can't be checked: another terminal, no
    /// tty, or a tmux pane (the tab shows tmux's own tty, not the pane's).
    public static func probe(context: TerminalContext?, sessionApp: String?) -> Probe? {
        guard let sessionApp, [TerminalTarget.iTerm, TerminalTarget.terminalApp].contains(sessionApp),
            let context, context.tmux == nil, let tty = context.tty
        else { return nil }
        return Probe(app: sessionApp, tty: tty)
    }

    /// Limits alerts are about Wisp's own cards and the user's spend, not the terminal.
    public static func applies(to group: AgentAlertGroup) -> Bool {
        group != .limits
    }

    /// "ttys003" from "/dev/ttys003", trimmed.
    private static func name(of tty: String) -> String {
        let trimmed = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/dev/") ? String(trimmed.dropFirst(5)) : trimmed
    }
}
