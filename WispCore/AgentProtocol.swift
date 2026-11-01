import Foundation

/// One message on Wisp's agent socket, decoded.
public enum AgentMessage: Equatable, Sendable {
    /// A hook call (or tool activity, sent as `tool`). Only PermissionRequest waits for a reply.
    case hook(AgentEvent)
    /// A statusLine snapshot. Never answered.
    case statusline(StatusLineSnapshot, source: AgentSource, terminal: String?)
    /// `wisp status` or `wisp spend`, answered with an `AgentReport`.
    case query(AgentQuery)
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
    }

    /// The envelope around `payload`, or nil when the payload isn't a JSON object.
    public static func envelope(kind: Kind, source: AgentSource, terminal: String?, payload: Data) -> Data? {
        guard let payloadJSON = try? JSONDecoder().decode(JSONValue.self, from: payload),
            case .object = payloadJSON
        else { return nil }
        var fields: [String: JSONValue] = [
            "v": .number(Double(version)), "kind": .string(kind.rawValue), "source": .string(source.rawValue),
            "payload": payloadJSON,
        ]
        if let terminal, !terminal.isEmpty { fields["terminal"] = .string(terminal) }
        return try? JSONEncoder().encode(JSONValue.object(fields))
    }

    /// How the helper sends a hook's JSON: tool activity is `tool`, sent without waiting for
    /// a reply, so a tool call never waits on Wisp. Everything else is `hook`.
    public static func kind(forHook payload: Data) -> Kind {
        let name = (try? JSONDecoder().decode(JSONValue.self, from: payload))?["hook_event_name"]?.stringValue
        return name.map { AgentSource.claude.toolHookEvents.contains($0) } == true ? .tool : .hook
    }

    public static func decode(_ data: Data) throws -> AgentMessage {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let version = json["v"]?.intValue else { return .hook(try AgentEvent.decode(data)) }
        let kindName = json["kind"]?.stringValue ?? "?"
        guard version <= Self.version, let kind = Kind(rawValue: kindName), let payload = json["payload"] else {
            return .unsupported("\(kindName) v\(version)")
        }
        let source = json["source"]?.stringValue.flatMap(AgentSource.init(rawValue:)) ?? .claude
        let terminal = json["terminal"]?.stringValue
        switch kind {
        case .hook, .tool: return .hook(AgentEvent(json: payload, source: source, terminal: terminal))
        case .statusline:
            return .statusline(StatusLineSnapshot(json: payload), source: source, terminal: terminal)
        case .query:
            let name = payload["query"]?.stringValue ?? "?"
            return AgentQuery(rawValue: name).map(AgentMessage.query) ?? .unsupported("query \(name)")
        }
    }
}
