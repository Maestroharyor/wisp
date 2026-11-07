import Foundation

/// The Approve and Deny Shortcuts actions: which request they may answer and what they say.
/// A saved Shortcut can be run from a web page (`shortcuts://run-shortcut`), so they answer only
/// the card on screen, only when it's a plain tool permission, and ask first by default.
public enum ShortcutAnswer {
    public struct Request: Equatable, Sendable {
        public let agent: String
        public let tool: String
        public let project: String
        public let prompt: PermissionPrompt
        /// The command, path or URL the card summarises; shown masked, and only with details on.
        public let summary: String

        public init(agent: String, tool: String, project: String, prompt: PermissionPrompt, summary: String = "") {
            self.agent = agent
            self.tool = tool
            self.project = project
            self.prompt = prompt
            self.summary = summary
        }
    }

    public enum Pick: Equatable, Sendable {
        case answer
        /// Why not, as the Shortcut's error.
        case refuse(String)
    }

    public static let nothingWaiting = "No request is waiting."
    public static let answerInNotch = "Answer this one in the notch."

    /// `front` is the prompt of the card on screen, nil when nothing waits. A plan or question
    /// there is refused rather than skipped, so no hidden request behind it gets answered.
    public static func pick(front: PermissionPrompt?) -> Pick {
        switch front {
        case .tool: .answer
        case .plan, .question: .refuse(answerInNotch)
        case nil: .refuse(nothingWaiting)
        }
    }

    /// "Claude Code wants to run a command (Bash) in wisp.", then what it runs (masked, as push's
    /// "Include details" shows it) unless details are hidden, then "Allow it?".
    public static func confirmation(_ request: Request, allow: Bool, hidden: Bool) -> String {
        let action = PushMessage.verb(tool: request.tool, prompt: request.prompt)
        let place = place(request.project, hidden: hidden)
        var lines = ["\(request.agent) wants to \(action) (\(request.tool))\(place)."]
        // A plan's text is the user's work and never shown, as with push.
        if !hidden, request.prompt == .tool,
            let detail = PushMessage.detail(tool: request.tool, summary: request.summary)
        {
            lines.append(detail)
        }
        lines.append(allow ? "Allow it?" : "Deny it?")
        return lines.joined(separator: "\n")
    }

    /// "Allowed Claude Code to run a command in wisp."
    public static func result(_ request: Request, allow: Bool, hidden: Bool) -> String {
        let action = PushMessage.verb(tool: request.tool, prompt: request.prompt)
        let place = place(request.project, hidden: hidden)
        return allow
            ? "Allowed \(request.agent) to \(action)\(place)."
            : "Denied \(request.agent)'s request to \(action)\(place)."
    }

    private static func place(_ project: String, hidden: Bool) -> String {
        hidden || project.isEmpty ? "" : " in \(project)"
    }
}
