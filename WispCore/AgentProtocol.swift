import Foundation

/// One message on Wisp's agent socket, decoded.
public enum AgentMessage: Equatable, Sendable {
    /// A hook call (or tool activity, sent as `tool`). Only PermissionRequest waits for a reply.
    case hook(AgentEvent)
    /// A statusLine snapshot. Never answered.
    case statusline(StatusLineSnapshot, source: AgentSource, terminal: String?)
    /// `wisp status` or `wisp spend`, answered with an `AgentReport`.
    case query(AgentQuery)
    /// `wisp activity`, or a script writing to the socket: a live activity to show, update or end.
    /// Answered with an `ActivityReply`, so the sender knows this Wisp understood it.
    case activity(ExternalActivityAction)
    /// A kind or version this build doesn't know, named for the log.
    case unsupported(String)
}

/// The JSON envelope the helper wraps every message in (see `docs/agent-protocol.md`):
/// `{"v": 1, "kind": "hook", "source": "claude", "terminal": "...", "payload": {...}}`.
/// Messages without `v` are the original format, a hook's JSON tagged with `wisp_source`.
public enum AgentProtocol {
    public static let version = 1

    public enum Kind: String, Sendable {
        case hook
        case statusline
        case tool
        case query
        case activity
    }

    /// What Wisp answers an `activity` message with: `{"ok":true}`, or `{"ok":false,"error":"…"}`
    /// when it understood the message but couldn't act on it.
    public enum ActivityReply: Equatable, Sendable {
        case accepted
        case rejected(String)

        public var encoded: String {
            var fields: [String: JSONValue] = [:]
            switch self {
            case .accepted: fields["ok"] = .bool(true)
            case .rejected(let error):
                fields["ok"] = .bool(false)
                fields["error"] = .string(error)
            }
            return (try? JSONEncoder().encode(JSONValue.object(fields))).map { String(decoding: $0, as: UTF8.self) }
                ?? ""
        }

        /// Nil for an empty or unknown reply: a Wisp too old to know `activity`.
        public init?(_ data: Data) {
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), case .bool(let ok) = json["ok"]
            else { return nil }
            self = ok ? .accepted : .rejected(json["error"]?.stringValue ?? "Wisp didn't take it.")
        }
    }

    /// The envelope around `payload`, or nil when the payload isn't a JSON object.
    /// `process` is the agent the helper runs under, so Wisp can tell when it has quit, and
    /// `context` is where in the terminal it runs, so Wisp can bring that pane forward.
    public static func envelope(
        kind: Kind, source: AgentSource, terminal: String?, process: AgentProcess? = nil,
        context: TerminalContext? = nil, payload: Data
    ) -> Data? {
        guard let payloadJSON = try? JSONDecoder().decode(JSONValue.self, from: payload),
            case .object = payloadJSON
        else { return nil }
        var fields: [String: JSONValue] = [
            "v": .number(Double(version)), "kind": .string(kind.rawValue), "source": .string(source.rawValue),
            "payload": payloadJSON,
        ]
        if let terminal, !terminal.isEmpty { fields["terminal"] = .string(terminal) }
        if let process { fields["process"] = process.json }
        if let context, !context.isEmpty { fields[TerminalContext.envelopeKey] = context.json }
        return try? JSONEncoder().encode(JSONValue.object(fields))
    }

    /// How the helper sends a hook's JSON: tool activity is `tool`, sent without waiting for
    /// a reply, so a tool call never waits on Wisp. Everything else is `hook`. Read through the
    /// adapter, so a tool hook installed outside the tool activity switch (Gemini's AfterTool)
    /// is still tool activity.
    public static func kind(forHook payload: Data, source: AgentSource = .claude) -> Kind {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: payload),
            let event = source.adapter.parse(json, terminal: nil)
        else { return .hook }
        return event.kind.isToolActivity ? .tool : .hook
    }

    /// A missing source reads as Claude Code, as protocol v1 always did. One no adapter knows
    /// is unsupported, so a request from it gets an empty reply.
    public static func decode(_ data: Data) throws -> AgentMessage {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let version = json["v"]?.intValue else {
            if let id = json["wisp_source"]?.stringValue, AgentSource(rawValue: id) == nil {
                return .unsupported("source \(id)")
            }
            return .hook(try AgentEvent.decode(data))
        }
        let kindName = json["kind"]?.stringValue ?? "?"
        guard version <= Self.version, let kind = Kind(rawValue: kindName), let payload = json["payload"] else {
            return .unsupported("\(kindName) v\(version)")
        }
        let id = json["source"]?.stringValue ?? AgentSource.claude.rawValue
        guard let source = AgentSource(rawValue: id) else { return .unsupported("source \(id)") }
        let terminal = json["terminal"]?.stringValue
        let process = AgentProcess(json: json["process"])
        let context = TerminalContext(json: json[TerminalContext.envelopeKey])
        switch kind {
        case .hook, .tool:
            guard var event = source.adapter.parse(payload, terminal: terminal) else {
                return .unsupported("hook payload")
            }
            event.process = process
            event.terminalContext = context
            return .hook(event)
        case .statusline:
            var snapshot = StatusLineSnapshot(json: payload)
            snapshot.process = process
            snapshot.terminalContext = context
            return .statusline(snapshot, source: source, terminal: terminal)
        case .query:
            let name = payload["query"]?.stringValue ?? "?"
            return AgentQuery(rawValue: name).map(AgentMessage.query) ?? .unsupported("query \(name)")
        case .activity:
            guard case .success(let action) = ExternalActivityAction.parse(json: payload) else {
                return .unsupported("activity payload")
            }
            return .activity(action)
        }
    }
}
