import Foundation

/// One line in a session's history.
public struct AgentTimelineEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case started, prompt, request, allowed, denied, waiting, done
    }

    public let id = UUID()
    public let date: Date
    public let kind: Kind
    public let text: String

    public static func == (lhs: AgentTimelineEntry, rhs: AgentTimelineEntry) -> Bool {
        lhs.date == rhs.date && lhs.kind == rhs.kind && lhs.text == rhs.text
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
    /// Tokens used so far, read from the transcript, and their estimated cost in dollars.
    public var usage: TokenUsage?
    public var cost: Double?
    public var state: State
    /// What happened in this session, oldest first, capped at `AgentSessions.timelineLimit`.
    public var timeline: [AgentTimelineEntry] = []
    /// "Allow All" was chosen: later requests are allowed without asking.
    public var autoApprove = false
    /// When the current turn began, for the elapsed timer.
    public var turnStarted: Date
    public var updated: Date
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
        switch event.kind {
        case .sessionStart:
            session.state = .idle
            Self.append(.started, "Session started", to: &session, at: date)
        case .userPromptSubmit:
            session.state = .running
            session.turnStarted = date
            Self.append(.prompt, "Prompt sent", to: &session, at: date)
        case .permissionRequest:
            session.state = .needsApproval
            let tool = event.toolName ?? "Tool"
            Self.append(.request, event.summary.isEmpty ? tool : "\(tool): \(event.summary)", to: &session, at: date)
        case .notification:
            if event.notificationType == "idle_prompt" || event.notificationType == "elicitation_dialog" {
                session.state = .waiting
                Self.append(.waiting, "Needs you", to: &session, at: date)
            }
        case .stop:
            session.state = .finished
            Self.append(.done, "Done", to: &session, at: date)
        case .sessionEnd, .other: break
        }
        sessions[event.sessionID] = session
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
        _ kind: AgentTimelineEntry.Kind, _ text: String, to session: inout AgentSession, at date: Date
    ) {
        session.timeline.append(AgentTimelineEntry(date: date, kind: kind, text: text))
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

    public mutating func setUsage(_ usage: TokenUsage, cost: Double?, session id: String) {
        guard var session = sessions[id] else { return }
        session.usage = usage
        session.cost = cost
        sessions[id] = session
    }

    public func session(_ id: String) -> AgentSession? { sessions[id] }

    public mutating func prune(now: Date, olderThan age: TimeInterval) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.updated) < age }
    }
}
