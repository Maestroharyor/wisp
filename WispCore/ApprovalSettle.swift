import Foundation

/// Which waiting requests an incoming hook event shows were answered somewhere else (the
/// terminal), so their cards can go. Settling only hands a request back: if a rule misfires,
/// the card goes but the terminal still asks.
public enum ApprovalSettle {
    /// What a waiting request is matched on.
    public struct Request<ID: Hashable & Sendable>: Equatable, Sendable {
        public let id: ID
        public let sessionID: String
        public let tool: String
        public let prompt: PermissionPrompt
        public let input: JSONValue?
        /// The subagent that asked, or nil for the main agent.
        public let agentID: String?

        public init(
            id: ID, sessionID: String, tool: String, prompt: PermissionPrompt, input: JSONValue?, agentID: String?
        ) {
            self.id = id
            self.sessionID = sessionID
            self.tool = tool
            self.prompt = prompt
            self.input = input
            self.agentID = agentID
        }

        /// From the PermissionRequest event that made the request.
        public init(id: ID, event: AgentEvent) {
            self.init(
                id: id, sessionID: event.sessionID, tool: event.toolName ?? "", prompt: event.prompt,
                input: event.rawToolInput, agentID: event.agentID)
        }
    }

    /// The requests `event` settles, in their order.
    /// - An interrupted turn (Codex's Interrupt) settles every request in its session.
    /// - A tool call that finished (PostToolUse) settles the request for that same call: same
    ///   session, agent (main or subagent) and tool. A tool request also needs the same input, so
    ///   a parallel call to the same tool doesn't settle it; a question or plan doesn't, since
    ///   its answer comes back inside the input.
    /// - PreToolUse never settles: tool hooks run in the background, so a call's own PreToolUse
    ///   can arrive after its request.
    public static func settled<ID>(_ requests: [Request<ID>], by event: AgentEvent) -> [ID] {
        let session = requests.filter { $0.sessionID == event.sessionID }
        switch event.kind {
        case .interrupt:
            return session.map(\.id)
        case .postToolUse:
            return session.filter {
                $0.matches(tool: event.toolName, input: event.rawToolInput, agentID: event.agentID)
            }
            .map(\.id)
        default:
            return []
        }
    }

    /// The requests a call that finished in the session's transcript settles, in their order.
    /// The same rule as PostToolUse, for the main agent, whose calls are the only ones there.
    /// The transcript keeps the model's own input, which Claude Code may fill out before it
    /// asks, so a tool request whose input holds every field of the call's counts as that call.
    public static func settled<ID>(_ requests: [Request<ID>], finished call: TranscriptCalls.Call, session: String)
        -> [ID]
    {
        requests.filter { request in
            request.sessionID == session && request.tool == call.tool && request.agentID == nil
                && (request.prompt != .tool || holds(request.input, every: call.input))
        }
        .map(\.id)
    }

    private static func holds(_ input: JSONValue?, every fields: JSONValue?) -> Bool {
        guard case .object(let wanted) = fields, case .object(let present) = input else { return input == fields }
        return wanted.allSatisfy { present[$0.key] == $0.value }
    }
}

extension ApprovalSettle.Request {
    /// The same agent and tool, and for a tool request the same input. A question or plan's
    /// answer comes back inside its input, so the input isn't compared for those.
    fileprivate func matches(tool: String?, input: JSONValue?, agentID: String?) -> Bool {
        self.tool == tool && self.agentID == agentID && (prompt != .tool || self.input == input)
    }
}
