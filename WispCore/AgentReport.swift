import Foundation

/// What `wisp status` and `wisp spend` ask Wisp for, as a `query` message's payload:
/// `{"query": "status"}`.
public enum AgentQuery: String, Codable, Sendable {
    case status
    case spend

    /// The payload the helper sends.
    public var payload: Data { Data(#"{"query":"\#(rawValue)"}"#.utf8) }
}

/// Wisp's answer to a query: live sessions, and spend when asked for. Its JSON is what
/// `wisp status --json` prints, so keys are only ever added (see `docs/agent-protocol.md`).
public struct AgentReport: Codable, Equatable, Sendable {
    public static let version = 1

    public var v = Self.version
    public var generated: Date
    /// Why details are hidden ("during a call"), or nil when they're shown.
    public var hidden: String?
    public var sessions: [Row]
    public var spend: Spend?

    public struct Row: Codable, Equatable, Sendable {
        /// Left out while details are hidden.
        public var id: String?
        public var project: String
        public var branch: String?
        public var agent: String
        /// "working", "needs you", "needs approval", "done", "idle" or "compacting".
        public var state: String
        public var model: String?
        public var contextPercent: Double?
        public var cost: Double?
        /// False when the cost is Wisp's estimate from the transcript.
        public var costIsReal: Bool
        /// The running tool, masked; only its verb while details are hidden.
        public var tool: String?
        public var toolSeconds: Double?
        /// How long the current turn has run, or the last turn took once it's done.
        public var turnSeconds: Double?
        /// Left out while details are hidden.
        public var folder: String?

        /// Unknown values are written as null, not left out, so every row has the same keys.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(project, forKey: .project)
            try container.encode(branch, forKey: .branch)
            try container.encode(agent, forKey: .agent)
            try container.encode(state, forKey: .state)
            try container.encode(model, forKey: .model)
            try container.encode(contextPercent, forKey: .contextPercent)
            try container.encode(cost, forKey: .cost)
            try container.encode(costIsReal, forKey: .costIsReal)
            try container.encode(tool, forKey: .tool)
            try container.encode(toolSeconds, forKey: .toolSeconds)
            try container.encode(turnSeconds, forKey: .turnSeconds)
            try container.encode(folder, forKey: .folder)
        }
    }

    public struct Spend: Codable, Equatable, Sendable {
        public var today: Double
        public var week: Double
        /// The last 7 days, oldest first.
        public var days: [Double]
        public var projects: [Project]
    }

    public struct Project: Codable, Equatable, Sendable {
        public var project: String
        public var today: Double
        public var week: Double
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(generated, forKey: .generated)
        try container.encode(hidden, forKey: .hidden)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(spend, forKey: .spend)
    }

    public init(generated: Date, hidden: String?, sessions: [Row], spend: Spend?) {
        self.generated = generated
        self.hidden = hidden
        self.sessions = sessions
        self.spend = spend
    }

    /// `hidden` is the reason details are hidden (`AgentPrivacy.reason`), or nil.
    public static func make(
        sessions: [AgentSession], spend: DailySpend, query: AgentQuery, now: Date, hidden: String?,
        calendar: Calendar = .current
    ) -> AgentReport {
        let rows = sessions.sorted { $0.latestActivity > $1.latestActivity }.map {
            row($0, now: now, hidden: hidden != nil)
        }
        let spendPart: Spend? =
            query == .spend
            ? Spend(
                today: spend.total(on: now, calendar: calendar),
                week: spend.total(lastDays: 7, ending: now, calendar: calendar),
                days: spend.recent(days: 7, ending: now, calendar: calendar),
                projects: spend.byProject(lastDays: 7, ending: now, calendar: calendar).map {
                    Project(project: $0.project, today: $0.today, week: $0.week)
                })
            : nil
        return AgentReport(generated: now, hidden: hidden, sessions: rows, spend: spendPart)
    }

    static func row(_ session: AgentSession, now: Date, hidden: Bool) -> Row {
        let tool = session.state == .running ? session.currentTool : nil
        let turn: TimeInterval? =
            switch session.state {
            case .running, .needsApproval: max(0, now.timeIntervalSince(session.turnStarted))
            case .finished: session.lastTurnDuration
            case .idle, .waiting: nil
            }
        return Row(
            id: hidden ? nil : session.id, project: session.project, branch: session.branch,
            agent: session.source.displayName, state: stateName(session), model: session.displayModel,
            contextPercent: session.contextPercent.map { ($0 * 10).rounded() / 10 },
            cost: session.cost.map { ($0 * 10_000).rounded() / 10_000 }, costIsReal: session.costIsReal,
            tool: tool?.label(hidden: hidden),
            toolSeconds: tool.map { max(0, now.timeIntervalSince($0.started)).rounded() },
            turnSeconds: turn.map { $0.rounded() }, folder: hidden || session.cwd.isEmpty ? nil : session.cwd)
    }

    static func stateName(_ session: AgentSession) -> String {
        if session.compacting { return "compacting" }
        switch session.state {
        case .running: return "working"
        case .waiting: return "needs you"
        case .needsApproval: return "needs approval"
        case .finished: return "done"
        case .idle: return "idle"
        }
    }

    // MARK: JSON

    public func encoded(pretty: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try? encoder.encode(self)
    }

    public static func decode(_ data: Data) -> AgentReport? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentReport.self, from: data)
    }
}
