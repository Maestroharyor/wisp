import Foundation

/// One line in a session's history.
public struct AgentTimelineEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case started, prompt, request, allowed, denied, waiting, done, compacted
    }

    public let id = UUID()
    public let date: Date
    public let kind: Kind
    public let text: String
    /// The command, path or URL behind a tool entry; left out in private mode.
    public let detail: String?

    public init(date: Date, kind: Kind, text: String, detail: String? = nil) {
        self.date = date
        self.kind = kind
        self.text = text
        self.detail = detail
    }

    public func display(hidden: Bool) -> String {
        guard let detail, !detail.isEmpty, !hidden else { return text }
        return "\(text): \(detail)"
    }

    public static func == (lhs: AgentTimelineEntry, rhs: AgentTimelineEntry) -> Bool {
        lhs.date == rhs.date && lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.detail == rhs.detail
    }
}

public struct AgentSession: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case running
        /// Claude is waiting for the user's next message or input.
        case waiting
        case needsApproval
        case finished
    }

    public let id: String
    public var project: String
    public var source: AgentSource = .claude
    public var terminal: String?
    public var cwd = ""
    public var transcriptPath: String?
    /// Tokens used so far, read from the transcript, and the cost in dollars: Claude Code's
    /// own figure once its status bar reports one (`costIsReal`), an estimate otherwise.
    public var usage: TokenUsage?
    public var cost: Double?
    public var costIsReal = false
    /// The model's name as Claude Code's status bar shows it.
    public var model: String?
    /// The model id from the transcript, for sessions without the status bar.
    public var modelID: String?
    /// Share of the context window in use, 0 to 100, when the agent reports it.
    public var contextPercent: Double?
    public var contextSize: Int?
    /// The context alert fired and hasn't re-armed yet.
    public var contextAlerted = false
    public var compacting = false
    public var linesAdded = 0
    public var linesRemoved = 0
    /// The whole session's length and the time spent waiting on the model, as reported.
    public var duration: TimeInterval?
    public var apiDuration: TimeInterval?
    public var branch: String?
    /// The latest status bar snapshot, for everything else it reports.
    public var extras = StatusLineSnapshot.Extras()
    public var state: State
    /// What happened in this session, oldest first, capped at `AgentSessions.timelineLimit`.
    public var timeline: [AgentTimelineEntry] = []
    /// "Allow All" was chosen: later requests are allowed without asking.
    public var autoApprove = false
    /// When the current turn began, for the elapsed timer.
    public var turnStarted: Date
    /// When the last turn finished; nil while one runs.
    public var turnEnded: Date?
    public var updated: Date
}

extension AgentSession {
    /// What a status bar snapshot can change.
    struct LiveFigures: Equatable {
        let cost: Double?
        let model: String?
        let contextPercent: Double?
        let lines: [Int]
        let compacting: Bool
    }

    var liveFigures: LiveFigures {
        LiveFigures(
            cost: cost, model: model, contextPercent: contextPercent, lines: [linesAdded, linesRemoved],
            compacting: compacting)
    }

    public var displayModel: String? { model ?? modelID.map(ModelName.display) }

    /// How long the last finished turn took.
    public var lastTurnDuration: TimeInterval? {
        turnEnded.map { max(0, $0.timeIntervalSince(turnStarted)) }
    }

    /// "Opus · 182k tokens · $0.41 · +120 −34". The cost has a "~" when it's Wisp's estimate.
    /// Empty when nothing is known yet.
    public var figures: String {
        var parts: [String] = []
        if let model = displayModel { parts.append(model) }
        if let usage { parts.append("\(TokenUsage.compact(usage.all)) tokens") }
        if let cost { parts.append((costIsReal ? "" : "~") + String(format: "$%.2f", cost)) }
        if linesAdded > 0 || linesRemoved > 0 { parts.append("+\(linesAdded) −\(linesRemoved)") }
        return parts.joined(separator: " · ")
    }
}

/// Live Claude Code sessions, driven by hook events.
public struct AgentSessions: Sendable {
    private var sessions: [String: AgentSession] = [:]

    public static let timelineLimit = 40

    public init() {}

    /// Newest activity first.
    public var list: [AgentSession] { sessions.values.sorted { $0.updated > $1.updated } }

    public var anyNeedsUser: Bool { sessions.values.contains { $0.state == .waiting || $0.state == .needsApproval } }

    public mutating func apply(_ event: AgentEvent, at date: Date) {
        if event.kind == .sessionEnd {
            sessions[event.sessionID] = nil
            return
        }
        var session =
            sessions[event.sessionID]
            ?? AgentSession(
                id: event.sessionID, project: event.project, source: event.source, state: .idle, turnStarted: date,
                updated: date)
        session.project = event.project
        if let terminal = event.terminal { session.terminal = terminal }
        if !event.cwd.isEmpty { session.cwd = event.cwd }
        if let path = event.transcriptPath { session.transcriptPath = path }
        session.updated = date
        // Compaction never outlives a turn; a PostCompact that never came mustn't leave it showing.
        if [.sessionStart, .userPromptSubmit, .stop].contains(event.kind) { session.compacting = false }
        switch event.kind {
        case .sessionStart:
            session.state = .idle
            Self.append(.started, "Session started", to: &session, at: date)
        case .userPromptSubmit:
            session.state = .running
            session.turnStarted = date
            session.turnEnded = nil
            Self.append(.prompt, "Prompt sent", to: &session, at: date)
        case .permissionRequest:
            session.state = .needsApproval
            let tool = event.toolName ?? "Tool"
            Self.append(.request, tool, detail: event.summary, to: &session, at: date)
        case .notification:
            if event.notificationType == "idle_prompt" || event.notificationType == "elicitation_dialog" {
                session.state = .waiting
                Self.append(.waiting, "Needs you", to: &session, at: date)
            }
        case .stop:
            // A turn Wisp didn't see start (it launched mid-turn) has no length to show.
            let sawStart = [.running, .waiting, .needsApproval].contains(session.state)
            session.state = .finished
            session.turnEnded = sawStart ? date : nil
            Self.append(.done, "Done", to: &session, at: date)
        case .preCompact:
            session.compacting = true
        case .postCompact:
            session.compacting = false
            // Claude Code reports no figure until the next request; the old one is wrong now.
            session.contextPercent = nil
            Self.append(.compacted, "Context compacted", to: &session, at: date)
        case .sessionEnd, .other: break
        }
        sessions[event.sessionID] = session
    }

    /// Live figures from Claude Code's status bar. Creates the session when Wisp started
    /// after it did, but never changes its state: only hooks do that. True when a working
    /// session's pill should show something new (its whole-number context or compaction);
    /// other states keep their pill as it is, so Done or Needs you isn't replayed.
    @discardableResult
    public mutating func apply(
        _ snapshot: StatusLineSnapshot, source: AgentSource, terminal: String?, branch: String?, at date: Date
    ) -> Bool {
        guard let id = snapshot.sessionID else { return false }
        let before = sessions[id].map { ($0.contextPercent?.rounded(), $0.compacting) }
        let figuresBefore = sessions[id].map(\.liveFigures)
        var session =
            sessions[id]
            ?? AgentSession(
                id: id, project: snapshot.project, source: source, state: .idle, turnStarted: date, updated: date)
        if !snapshot.cwd.isEmpty {
            session.cwd = snapshot.cwd
            session.project = snapshot.project
        }
        if let terminal, !terminal.isEmpty { session.terminal = terminal }
        if let path = snapshot.transcriptPath { session.transcriptPath = path }
        if let cost = snapshot.cost {
            session.cost = cost
            session.costIsReal = true
        }
        if let model = snapshot.model { session.model = model }
        session.contextSize = snapshot.contextSize ?? session.contextSize
        if let percent = snapshot.contextPercent {
            session.contextPercent = percent
            session.compacting = false
        }
        session.linesAdded = snapshot.linesAdded ?? session.linesAdded
        session.linesRemoved = snapshot.linesRemoved ?? session.linesRemoved
        session.duration = snapshot.duration ?? session.duration
        session.apiDuration = snapshot.apiDuration ?? session.apiDuration
        session.branch = snapshot.branch ?? branch ?? session.branch
        session.extras = snapshot.extras
        // Claude Code also re-runs the bar on timers; only a change counts as activity, so an
        // idle session doesn't jump to the top or escape pruning.
        if figuresBefore != session.liveFigures { session.updated = date }
        sessions[id] = session
        guard session.state == .running, let before else { return false }
        return before.0 != session.contextPercent?.rounded() || before.1 != session.compacting
    }

    /// The checked-out branch, read from the session's folder.
    public mutating func setBranch(_ branch: String?, session id: String) {
        guard let branch, sessions[id]?.branch != branch else { return }
        sessions[id]?.branch = branch
    }

    public mutating func setModelID(_ model: String?, session id: String) {
        guard let model, sessions[id]?.modelID != model else { return }
        sessions[id]?.modelID = model
    }

    /// The context percentage to alert about, once per climb past `threshold`.
    public mutating func contextAlert(session id: String, threshold: Double) -> Double? {
        guard var session = sessions[id] else { return nil }
        let result = ContextUsage.alert(
            percent: session.contextPercent, threshold: threshold, alerted: session.contextAlerted)
        session.contextAlerted = result.alerted
        sessions[id] = session
        return result.fire ? session.contextPercent : nil
    }

    /// Adds a line that didn't come from a hook event, such as an answer given in the notch.
    public mutating func record(_ kind: AgentTimelineEntry.Kind, _ text: String, session id: String, at date: Date) {
        guard var session = sessions[id] else { return }
        Self.append(kind, text, to: &session, at: date)
        sessions[id] = session
    }

    public mutating func allowAll(session id: String) {
        sessions[id]?.autoApprove = true
    }

    public func shouldAutoApprove(_ id: String) -> Bool { sessions[id]?.autoApprove == true }

    private static func append(
        _ kind: AgentTimelineEntry.Kind, _ text: String, detail: String? = nil, to session: inout AgentSession,
        at date: Date
    ) {
        session.timeline.append(AgentTimelineEntry(date: date, kind: kind, text: text, detail: detail))
        if session.timeline.count > timelineLimit {
            session.timeline.removeFirst(session.timeline.count - timelineLimit)
        }
    }

    /// An approval was answered (from the notch or the terminal): back to work.
    public mutating func resolveApproval(session id: String, at date: Date) {
        guard var session = sessions[id], session.state == .needsApproval else { return }
        session.state = .running
        session.updated = date
        sessions[id] = session
    }

    /// Tokens from the transcript. The estimated cost is kept only while Claude Code hasn't
    /// reported a real one.
    public mutating func setUsage(_ usage: TokenUsage, cost: Double?, session id: String) {
        guard var session = sessions[id] else { return }
        session.usage = usage
        if !session.costIsReal { session.cost = cost }
        sessions[id] = session
    }

    public func session(_ id: String) -> AgentSession? { sessions[id] }

    public mutating func prune(now: Date, olderThan age: TimeInterval) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.updated) < age }
    }
}
