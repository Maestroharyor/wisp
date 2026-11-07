import Foundation

/// Approvals waiting for a reply from the phone, by nonce. A reply counts only when its nonce
/// belongs to a pending, unexpired approval, and only once. Anyone can post to a public reply
/// topic, so nothing in a message is used beyond the nonce and the decision.
public struct PushReplies<ID: Hashable & Sendable>: Sendable {
    private struct Pending: Sendable {
        let id: ID
        let expires: Date
    }

    private var pending: [String: Pending] = [:]

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }
    public var count: Int { pending.count }

    public mutating func register(nonce: String, for id: ID, expires: Date) {
        pending[nonce] = Pending(id: id, expires: expires)
    }

    /// The approval was answered on the Mac, handed back or timed out: its nonce stops working.
    public mutating func remove(_ id: ID) {
        pending = pending.filter { $0.value.id != id }
    }

    public mutating func removeExpired(now: Date) {
        pending = pending.filter { $0.value.expires > now }
    }

    /// The approval and decision for one line of ntfy's JSON stream, using up the nonce. Nil for
    /// keepalives, malformed lines, unknown, expired or used nonces.
    public mutating func resolve(line: String, now: Date) -> (id: ID, decision: PushDecision)? {
        guard let reply = PushReplyLine.parse(line), let match = pending[reply.nonce] else { return nil }
        pending[reply.nonce] = nil
        guard match.expires > now else { return nil }
        return (match.id, reply.decision)
    }
}

/// One line of `/<topic>/json`: an `open`, `keepalive` or `message` event as a JSON object.
public enum PushReplyLine {
    /// Reply bodies are tiny; anything longer isn't one of Wisp's.
    static let maximumBody = 512

    public static func parse(_ line: String) -> (nonce: String, decision: PushDecision)? {
        guard let data = line.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
            let event = try? JSONDecoder().decode(JSONValue.self, from: data),
            event["event"]?.stringValue == "message", let body = event["message"]?.stringValue,
            body.utf8.count <= maximumBody,
            let fields = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)),
            let nonce = fields["nonce"]?.stringValue, PushTopic.isValid(nonce),
            let decision = fields["decision"]?.stringValue.flatMap(PushDecision.init(rawValue:))
        else { return nil }
        return (nonce, decision)
    }
}
