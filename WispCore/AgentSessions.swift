import Foundation

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
    public var state: State
    /// When the current turn began, for the elapsed timer.
    public var turnStarted: Date
    public var updated: Date
}

/// Live Claude Code sessions, driven by hook events.
public struct AgentSessions: Sendable {
    private var sessions: [String: AgentSession] = [:]

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
            ?? AgentSession(id: event.sessionID, project: event.project, state: .idle, turnStarted: date, updated: date)
        session.project = event.project
        session.updated = date
        switch event.kind {
        case .sessionStart: session.state = .idle
        case .userPromptSubmit:
            session.state = .running
            session.turnStarted = date
        case .permissionRequest: session.state = .needsApproval
        case .notification:
            if event.notificationType == "idle_prompt" || event.notificationType == "elicitation_dialog" {
                session.state = .waiting
            }
        case .stop: session.state = .finished
        case .sessionEnd, .other: break
        }
        sessions[event.sessionID] = session
    }

    /// An approval was answered (from the notch or the terminal): back to work.
    public mutating func resolveApproval(session id: String, at date: Date) {
        guard var session = sessions[id], session.state == .needsApproval else { return }
        session.state = .running
        session.updated = date
        sessions[id] = session
    }

    public mutating func prune(now: Date, olderThan age: TimeInterval) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.updated) < age }
    }
}
