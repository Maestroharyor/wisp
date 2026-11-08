import Foundation

// ntfy facts this file relies on, checked against docs.ntfy.sh on 2026-11-07 ("Publish",
// "Subscribe › API", "Action buttons", "Updating + deleting notifications", "Limitations"):
// - Publishing as JSON: POST to the server root with `topic` in the body. Other fields used here:
//   `message`, `title`, `tags`, `priority` (1 to 5, 3 is the default), `actions`, `sequence_id`.
// - Up to three action buttons. An `http` action has `action: "http"`, `label`, `url`, and
//   optional `method` (POST by default), `headers`, `body` and `clear` (dismiss the notification
//   once the request succeeds).
// - Messages are up to 4,096 bytes; longer ones turn into attachments, so text is kept short.
// - Publishing again with the same `sequence_id` updates the earlier notification on clients
//   that support it (the web and Android apps are named; iOS isn't confirmed).
// - Access tokens go in `Authorization: Bearer tk_...`.
// - ntfy.sh allows 250 messages a day and a burst of 60 requests per visitor, refilled one every
//   5 seconds; `PushPolicy` stays well inside that.

/// One button on a pushed notification: an `http` action that posts `body` to `url`.
public struct PushAction: Equatable, Sendable {
    public let label: String
    public let url: String
    public let body: String
    public let headers: [String: String]
}

/// A notification for the phone, before it becomes ntfy's JSON.
public struct PushNotice: Equatable, Sendable {
    public var title: String
    public var message: String
    /// ntfy's 1 (min) to 5 (max); 3 is the default.
    public var priority: Int
    /// ntfy shows known tags as emoji before the title.
    public var tags: [String]
    public var actions: [PushAction] = []
    /// Lets a later message replace this one on the phone.
    public var sequenceID: String?
}

/// The decision a reply button sends back.
public enum PushDecision: String, Equatable, Sendable {
    case allow
    case deny
}

/// Builds what Wisp pushes. Masked by default: no commands, file paths, diffs, prompts or folder
/// paths, only the agent, the kind of request and the project's name, and not even that while
/// agent details are hidden (`AgentPrivacy`). "Add the command or file name" adds a short masked summary.
public enum PushMessage {
    /// Characters of detail at most; ntfy's own limit is 4,096 bytes.
    static let detailLimit = 160

    /// What the user sees and what a button needs to reply.
    public struct Approval: Sendable {
        public let agent: String
        public let tool: String
        public let prompt: PermissionPrompt
        /// The command, path or description the request is about.
        public let summary: String
        public let project: String

        public init(agent: String, tool: String, prompt: PermissionPrompt, summary: String, project: String) {
            self.agent = agent
            self.tool = tool
            self.prompt = prompt
            self.summary = summary
            self.project = project
        }
    }

    /// Where reply buttons post and how they prove they can.
    public struct Reply: Sendable {
        /// `<server>/<reply topic>`.
        public let url: URL
        /// Single use, for this approval only.
        public let nonce: String
        /// For a protected server; the buttons send it so the phone can post to the reply topic.
        public let token: String?

        public init(url: URL, nonce: String, token: String?) {
            self.url = url
            self.nonce = nonce
            self.token = token
        }
    }

    public static func approval(
        _ request: Approval, reply: Reply, hidden: Bool, includeDetails: Bool, sequenceID: String
    ) -> PushNotice {
        let place = hidden || request.project.isEmpty ? "" : " in \(request.project)"
        var message = "\(request.agent) wants to \(verb(tool: request.tool, prompt: request.prompt))\(place)."
        // A plan's text is the user's work, so it never goes, details or not.
        if includeDetails, !hidden, request.prompt == .tool,
            let detail = detail(tool: request.tool, summary: request.summary)
        {
            message += "\n" + detail
        }
        let headers = reply.token.map { ["Authorization": "Bearer \($0)"] } ?? [:]
        let actions = [PushDecision.allow, .deny].map { decision in
            PushAction(
                label: decision == .allow ? "Allow" : "Deny", url: reply.url.absoluteString,
                body: replyBody(nonce: reply.nonce, decision: decision), headers: headers)
        }
        return PushNotice(
            title: request.prompt == .plan ? "Approve plan" : "Permission request", message: message, priority: 4,
            tags: ["lock"], actions: actions, sequenceID: sequenceID)
    }

    /// Replaces an approval's notification once it's answered on the Mac or times out, where the
    /// phone supports updates; elsewhere it arrives as a quiet notification of its own.
    public static func settled(sequenceID: String, answered: Bool) -> PushNotice {
        PushNotice(
            title: "Permission request", message: answered ? "Answered on the Mac." : "Handed back to the terminal.",
            priority: 2, tags: ["white_check_mark"], sequenceID: sequenceID)
    }

    public static func needsYou(agent: String, project: String, hidden: Bool) -> PushNotice {
        PushNotice(
            title: "Needs you", message: "\(agent) is waiting for you\(place(project, hidden: hidden)).", priority: 4,
            tags: ["bell"])
    }

    /// The session summary's first sentence goes along only with "Add the command or file name" on and details
    /// shown, since it can name files and commands.
    public static func done(
        agent: String, project: String, hidden: Bool, summary: String? = nil, includeDetails: Bool = false
    ) -> PushNotice {
        var message = "\(agent) finished\(place(project, hidden: hidden))."
        if includeDetails, !hidden, let summary {
            let sentence = SessionSummaryText.firstSentence(summary)
            if !sentence.isEmpty { message += " " + sentence }
        }
        return PushNotice(title: "Done", message: message, priority: 3, tags: ["white_check_mark"])
    }

    /// `text` is Wisp's own notice ("5 h limit 82%"), which holds no session details.
    public static func limit(_ text: String) -> PushNotice {
        PushNotice(title: "Usage limit", message: text, priority: 3, tags: ["hourglass"])
    }

    public static func budget(_ text: String) -> PushNotice {
        PushNotice(title: "Daily budget", message: text, priority: 3, tags: ["moneybag"])
    }

    /// The task's title is often the prompt, so it never goes; only the agent and the repository.
    public static func cloud(_ event: CloudEvent, hidden: Bool) -> PushNotice {
        let agent = event.task.source.displayName
        let place = place(event.task.repository ?? "", hidden: hidden)
        switch event.kind {
        case .finished:
            return PushNotice(
                title: "Cloud task ready", message: "A \(agent) task is ready\(place).", priority: 3,
                tags: ["white_check_mark"])
        case .failed:
            return PushNotice(
                title: "Cloud task failed", message: "A \(agent) task failed\(place).", priority: 4, tags: ["x"])
        case .checksFailed:
            return PushNotice(
                title: "Checks failed", message: "Checks failed on a \(agent) pull request\(place).", priority: 4,
                tags: ["warning"])
        }
    }

    public static let test = PushNotice(
        title: "Wisp", message: "Phone notifications are working.", priority: 3, tags: ["sparkles"])

    /// The reply button's body: the nonce and the decision, nothing else.
    public static func replyBody(nonce: String, decision: PushDecision) -> String {
        let fields: JSONValue = .object(["nonce": .string(nonce), "decision": .string(decision.rawValue)])
        return (try? encode(fields)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// ntfy's publish JSON, for a POST to the server root.
    public static func json(topic: String, notice: PushNotice) throws -> Data {
        var fields: [String: JSONValue] = [
            "topic": .string(topic), "title": .string(notice.title), "message": .string(notice.message),
            "priority": .number(Double(min(max(notice.priority, 1), 5))),
            "tags": .array(notice.tags.map(JSONValue.string)),
        ]
        if !notice.actions.isEmpty {
            fields["actions"] = .array(
                notice.actions.prefix(3).map { action in
                    var item: [String: JSONValue] = [
                        "action": .string("http"), "label": .string(action.label), "url": .string(action.url),
                        "method": .string("POST"), "body": .string(action.body), "clear": .bool(true),
                    ]
                    if !action.headers.isEmpty { item["headers"] = .object(action.headers.mapValues(JSONValue.string)) }
                    return .object(item)
                })
        }
        if let sequenceID = notice.sequenceID { fields["sequence_id"] = .string(sequenceID) }
        return try encode(.object(fields))
    }

    /// What the request would do, in words that give nothing away.
    static func verb(tool: String, prompt: PermissionPrompt) -> String {
        if prompt == .plan { return "start on a plan" }
        switch tool {
        case "Bash": return "run a command"
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": return "edit a file"
        case "Read": return "read a file"
        case "Grep", "Glob": return "search files"
        case "WebFetch": return "fetch a web page"
        case "WebSearch": return "search the web"
        case "Task", "Agent": return "start a subagent"
        default: return "use a tool"
        }
    }

    /// The masked summary for "Add the command or file name": a file's name rather than its path, a page's
    /// host, or the first line of a command with likely secrets masked.
    static func detail(tool: String, summary: String) -> String? {
        let text: String
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read", "apply_patch":
            text = summary.isEmpty ? "" : URL(fileURLWithPath: summary).lastPathComponent
        case "WebFetch":
            text = URL(string: summary)?.host ?? ""
        default:
            let line = summary.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            text = ToolLabel.mask(line).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        return text.count <= detailLimit ? text : String(text.prefix(detailLimit - 1)) + "…"
    }

    private static func place(_ project: String, hidden: Bool) -> String {
        hidden || project.isEmpty ? "" : " in \(project)"
    }

    private static func encode(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
