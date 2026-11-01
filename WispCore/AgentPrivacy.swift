import Foundation

/// When Wisp hides the parts of agent sessions that can give away work: shell commands,
/// file paths and URLs, the folder, the session's name and ID. Project, branch, model and
/// figures stay. macOS has no public way to tell an app the screen is being shared, so
/// calls are judged from the microphone, and a manual switch covers the rest.
public enum AgentPrivacy {
    public enum Mode: String, CaseIterable, Sendable {
        case never
        case duringCalls
        case always

        public static let `default` = Mode.duringCalls
    }

    /// Shown in place of a hidden value.
    public static let placeholder = "Hidden"

    public static func hidden(mode: Mode, onCall: Bool, manual: Bool) -> Bool {
        if manual { return true }
        switch mode {
        case .never: return false
        case .duringCalls: return onCall
        case .always: return true
        }
    }

    /// Browsers host calls (Meet, Teams, Zoom on the web) that often have no calendar event.
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "company.thebrowser.dia", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen",
    ]

    /// Stricter than the meeting pill: a browser on the mic counts too, since hiding details
    /// during dictation costs little and showing them during a call can't be undone.
    public static func onCall(micInUse: Bool, inputBundleIDs: [String], meetingInProgress: Bool) -> Bool {
        guard micInUse else { return false }
        if inputBundleIDs.contains(where: browsers.contains) { return true }
        return MicUse.classify(inputBundleIDs: inputBundleIDs, meetingInProgress: meetingInProgress) == .call
    }

    /// An approval's command or path, or nil when there's none to show.
    public static func summary(_ summary: String, hidden: Bool) -> String? {
        hidden || summary.isEmpty ? nil : summary
    }

    /// Why details are hidden, to finish "Commands and file names are hidden …"; nil when they're
    /// shown. The setting or a call comes before the manual switch: those keep hiding when the
    /// switch is turned off.
    public static func reason(mode: Mode, onCall: Bool, manual: Bool) -> String? {
        switch mode {
        case .always: return "by Settings › Agents › Privacy"
        case .duringCalls where onCall: return "during a call"
        default: return manual ? "until you show them" : nil
        }
    }

    public static func allowedNotice(tool: String?, summary: String, hidden: Bool) -> String {
        let tool = tool ?? "a tool"
        return "Allowed " + (self.summary(summary, hidden: hidden) ?? tool)
    }
}
