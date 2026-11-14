import Foundation

/// Where one coding agent stands with Wisp, for its row in Settings › Agents.
public enum IntegrationStatus: Equatable, Sendable {
    /// Hooks are current and a session has been seen since Wisp started.
    case connected
    /// Hooks are current; no session yet.
    case ready
    /// Wisp's hooks are there but from an older version, or with an old approval wait.
    case needsUpdate
    /// Watched by its process alone, with no hooks to install.
    case monitor
    case notInstalled
    /// The hooks call another copy of Wisp (a dev build, a moved app).
    case otherCopy

    /// What the row's buttons do; each uses the existing install and remove paths.
    public enum Action: Equatable, Sendable {
        case install
        case update
        /// Reinstalls current hooks; the file as it was is saved beside it.
        case repair
        case remove
        /// Points hooks that call another copy at this one.
        case useHere

        public var title: String {
            switch self {
            case .install: "Install"
            case .update: "Update"
            case .repair: "Repair"
            case .remove: "Remove"
            case .useHere: "Use this Wisp"
            }
        }
    }

    public init(link: HookLink, sessionSeen: Bool, processOnly: Bool = false) {
        if processOnly {
            self = .monitor
            return
        }
        switch link {
        case .none: self = .notInstalled
        case .this: self = sessionSeen ? .connected : .ready
        case .outdated: self = .needsUpdate
        case .other: self = .otherCopy
        }
    }

    public var label: String {
        switch self {
        case .connected: "Connected"
        case .ready: "Ready"
        case .needsUpdate: "Needs update"
        case .monitor: "Monitor"
        case .notInstalled: "Not installed"
        case .otherCopy: "Another Wisp"
        }
    }

    public var actions: [Action] {
        switch self {
        case .notInstalled: [.install]
        case .needsUpdate: [.update, .remove]
        case .ready, .connected: [.repair, .remove]
        case .otherCopy: [.useHere, .remove]
        case .monitor: []
        }
    }

    /// What Wisp does with the agent, as short words for its row: live context, session
    /// lifecycle, tool activity, approvals, answering questions and jumping to its terminal.
    public static func capabilities(_ adapter: AgentAdapter) -> [String] {
        let can = adapter.capabilities
        return [
            can.contains(.statusLine) || can.contains(.limits) ? "context" : nil,
            "lifecycle",
            can.contains(.toolActivity) ? "tools" : nil,
            can.contains(.approve) ? "approve" : nil,
            can.contains(.answerQuestions) ? "answer" : nil,
            "jump",
        ].compactMap { $0 }
    }

    /// What Wisp does with an agent it knows only by its process (`KnownAgents`).
    public static let monitorCapabilities = ["running", "jump"]
}
