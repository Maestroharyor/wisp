import Foundation

/// How a permission request, plan or question ended.
public enum ApprovalOutcome: String, Codable, CaseIterable, Sendable {
    /// Allowed (or a plan approved) from Wisp: the card, a key or the phone.
    case allowed
    case denied
    /// A question answered from Wisp.
    case answered
    /// Answered in the terminal, or handed back to it from the card.
    case terminal
    /// Allowed without asking, by Allow All.
    case rule
    /// Nobody answered in Wisp before the hook's wait ran out, so the terminal asked.
    case timedOut

    public var title: String {
        switch self {
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .answered: "Answered"
        case .terminal: "Answered in the terminal"
        case .rule: "By a rule"
        case .timedOut: "Timed out"
        }
    }
}

/// One request and how it ended. Holds the card's short summary (masked, first line) and
/// nothing more of the command, file or plan; no summary at all while details were hidden.
public struct ApprovalRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: String
    public var project: String
    public var source: AgentSource
    public var tool: String
    public var summary: String?
    public var outcome: ApprovalOutcome
    public var date: Date

    public init(
        id: UUID = UUID(), sessionID: String, project: String, source: AgentSource, tool: String, summary: String?,
        outcome: ApprovalOutcome, date: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.project = project
        self.source = source
        self.tool = tool
        self.summary = summary
        self.outcome = outcome
        self.date = date
    }

    /// What's stored of a request's summary: masked, first line, cut like a history command.
    /// Nil while details are hidden, or when there's nothing to keep.
    public static func summary(_ summary: String, hidden: Bool) -> String? {
        guard !hidden else { return nil }
        let clean = SessionRecorder.clean(summary)
        return clean.isEmpty ? nil : clean
    }

    /// Questions and plans aren't tool calls, so rules never cover them.
    public var isToolRequest: Bool { PermissionPrompt(tool: tool) == .tool }
}

/// The last requests and how each ended, newest first: at most `limit`, none older than
/// `maxAge`. Saved beside the session history.
public struct ApprovalLog: Codable, Equatable, Sendable {
    public private(set) var records: [ApprovalRecord] = []

    public static let limit = 200
    public static let maxAge: TimeInterval = 7 * 24 * 3600
    public static let version = 1

    public init(records: [ApprovalRecord] = []) {
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case version, records
    }

    /// One bad record is skipped instead of losing the rest.
    private struct Lenient: Decodable {
        let record: ApprovalRecord?
        init(from decoder: Decoder) throws { record = try? ApprovalRecord(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([Lenient].self, forKey: .records).compactMap(\.record)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(records, forKey: .records)
    }

    /// The saved file, newest first and pruned. Throws only when the file as a whole can't be read.
    public static func decode(_ data: Data, now: Date) throws -> ApprovalLog {
        var log = try JSONDecoder().decode(ApprovalLog.self, from: data)
        log.records.sort { $0.date > $1.date }
        log.prune(now: now)
        return log
    }

    public mutating func add(_ record: ApprovalRecord, now: Date) {
        let index = records.firstIndex { $0.date <= record.date } ?? records.endIndex
        records.insert(record, at: index)
        prune(now: now)
    }

    public mutating func clear() { records = [] }

    public mutating func prune(now: Date) {
        records = Array(records.filter { now.timeIntervalSince($0.date) < Self.maxAge }.prefix(Self.limit))
    }

    /// Records for one session and one outcome; nil means any.
    public func filtered(session: String?, outcome: ApprovalOutcome?) -> [ApprovalRecord] {
        records.filter { record in
            (session.map { record.sessionID == $0 } ?? true) && (outcome.map { record.outcome == $0 } ?? true)
        }
    }

    /// Each session with records, newest first, for the session filter.
    public var sessions: [(id: String, project: String)] {
        var seen: Set<String> = []
        return records.compactMap { record in
            seen.insert(record.sessionID).inserted ? (record.sessionID, record.project) : nil
        }
    }

    /// The newest `count` tool requests, which rule suggestions are measured against.
    public func recentToolRequests(_ count: Int) -> [ApprovalRecord] {
        Array(records.lazy.filter(\.isToolRequest).prefix(count))
    }
}
