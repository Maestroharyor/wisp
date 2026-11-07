import Foundation

/// A coding agent that works in the cloud rather than on this Mac.
public enum CloudSource: String, CaseIterable, Codable, Sendable {
    /// Codex cloud tasks, through the `codex` CLI's own login.
    case codex
    /// GitHub Copilot coding agent tasks, through `gh agent-task`.
    case copilot
    /// Cursor Cloud Agents, through its API with a key from the Keychain.
    case cursor

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .cursor: "Cursor"
        }
    }

    public var symbol: String {
        switch self {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .copilot: "person.badge.clock"
        case .cursor: "cursorarrow.rays"
        }
    }
}

/// Where a cloud task is, in one vocabulary for every source.
public enum CloudStatus: String, Sendable {
    case queued
    case running
    /// The agent asked the user something.
    case waiting
    /// Finished, with changes or a pull request to review.
    case ready
    case failed
    case cancelled

    /// Still working, so polling stays quick.
    public var inFlight: Bool { self == .queued || self == .running }

    public var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Working"
        case .waiting: "Needs you"
        case .ready: "Ready"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

/// A pull request's CI, counted from `gh pr checks`.
public struct CloudChecks: Equatable, Sendable {
    public var passed: Int
    public var failed: Int
    public var pending: Int

    public init(passed: Int, failed: Int, pending: Int) {
        self.passed = passed
        self.failed = failed
        self.pending = pending
    }

    public enum State: Sendable {
        case passing, pending, failing
    }

    /// Any failure makes it red, even while others still run.
    public var state: State {
        if failed > 0 { return .failing }
        return pending > 0 ? .pending : .passing
    }
}

/// One cloud agent task from any source.
public struct CloudTask: Identifiable, Equatable, Sendable {
    public var source: CloudSource
    /// The source's own id, as its CLI or API takes it back.
    public var taskID: String
    public var title: String
    public var status: CloudStatus
    /// Where the task is shown on the web.
    public var url: URL?
    public var pullRequest: URL?
    /// False once the pull request is merged or closed, so its checks stop being read.
    public var pullRequestOpen: Bool
    /// `owner/repo`, or the environment's label for Codex.
    public var repository: String?
    public var updatedAt: Date
    public var checks: CloudChecks?
    /// False when `status` is a guess (a Cursor agent whose latest run wasn't read), so it's
    /// shown but never announced or compared against.
    public var statusKnown: Bool

    public init(
        source: CloudSource, taskID: String, title: String, status: CloudStatus, url: URL?, pullRequest: URL?,
        repository: String?, updatedAt: Date, checks: CloudChecks? = nil, pullRequestOpen: Bool = true,
        statusKnown: Bool = true
    ) {
        self.statusKnown = statusKnown
        self.source = source
        self.taskID = taskID
        self.title = title
        self.status = status
        self.url = url
        self.pullRequest = pullRequest
        self.pullRequestOpen = pullRequestOpen
        self.repository = repository
        self.updatedAt = updatedAt
        self.checks = checks
    }

    public var id: String { source.rawValue + ":" + taskID }

    /// `codex cloud apply` takes a finished Codex task's diff into a local checkout.
    public var canApply: Bool { source == .codex && status == .ready }
}

/// A Cursor agent from the list, before its latest run is read.
public struct CursorAgent: Equatable, Sendable {
    public let id: String
    public let name: String
    /// `ACTIVE` in the API; `IDLE` otherwise (archived ones are left out).
    public let active: Bool
    public let url: URL?
    public let updatedAt: Date
    public let latestRunID: String?

    public init(id: String, name: String, active: Bool, url: URL?, updatedAt: Date, latestRunID: String?) {
        self.id = id
        self.name = name
        self.active = active
        self.url = url
        self.updatedAt = updatedAt
        self.latestRunID = latestRunID
    }
}

/// What a Cursor run adds: its status and the pull request it opened.
public struct CursorRun: Equatable, Sendable {
    public let status: CloudStatus?
    public let pullRequest: URL?
    public let repository: String?
}

/// How often to look again: about every 2 minutes while anything runs or a pull request's
/// checks are pending, every 15 minutes for a while after, and not at all once things have
/// been quiet for `idleWindow`, until Wisp wakes it (the Agents widget opens, Settings change,
/// the Mac wakes).
public struct CloudPollSchedule: Sendable {
    public static let busy: Duration = .seconds(120)
    public static let idle: Duration = .seconds(900)
    /// How long after the last activity the slow checks continue.
    public static let idleWindow: TimeInterval = 2 * 3600
    /// Pending checks on their own keep the quick pace this long; stuck checks then count as idle.
    public static let checksCap: TimeInterval = 3600

    private var lastActive: Date?
    /// When each task's checks were first seen pending, so each pull request gets its own hour.
    private var checksPendingSince: [String: Date] = [:]

    public init() {}

    /// Restarts the idle window, as if something had just run.
    public mutating func wake(now: Date) { lastActive = now }

    /// The wait before the next look, or nil to stop.
    public mutating func next(tasks: [CloudTask], now: Date) -> Duration? {
        let running = tasks.contains { $0.status.inFlight }
        let pending = Set(tasks.filter { $0.checks?.state == .pending }.map(\.id))
        checksPendingSince = checksPendingSince.filter { pending.contains($0.key) }
        for id in pending where checksPendingSince[id] == nil { checksPendingSince[id] = now }
        let checking = checksPendingSince.values.contains { now.timeIntervalSince($0) < Self.checksCap }
        let busy = running || checking
        if busy || lastActive == nil { lastActive = now }
        if busy { return Self.busy }
        guard let lastActive, now.timeIntervalSince(lastActive) < Self.idleWindow else { return nil }
        return Self.idle
    }
}

/// Parsers give a task with no readable time `Date.distantPast`; this gives it the time Wisp
/// first saw it instead, so it shows in the lane and can still raise a notice.
public struct CloudFirstSeen: Sendable {
    private var seen: [String: Date] = [:]

    public init() {}

    public mutating func stamp(_ tasks: [CloudTask], now: Date) -> [CloudTask] {
        tasks.map { task in
            guard task.updatedAt == .distantPast else { return task }
            var task = task
            task.updatedAt = seen[task.id] ?? now
            seen[task.id] = task.updatedAt
            return task
        }
    }

    /// Forgets a source's tasks, for when it's turned off.
    public mutating func forget(_ source: CloudSource) {
        seen = seen.filter { !$0.key.hasPrefix(source.rawValue + ":") }
    }
}

/// Something worth a notice: a task finished or failed, or its pull request's checks went red.
public struct CloudEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case finished, failed, checksFailed
    }

    public let kind: Kind
    public let task: CloudTask

    public init(kind: Kind, task: CloudTask) {
        self.kind = kind
        self.task = task
    }

    public var symbol: String {
        switch kind {
        case .finished: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .checksFailed: "exclamationmark.triangle.fill"
        }
    }

    /// The notch's notice. The title is often the prompt, so it's left out while details are hidden.
    public func notice(hidden: Bool) -> String {
        let head: String
        switch kind {
        case .finished: head = "\(task.source.displayName) task ready"
        case .failed: head = "\(task.source.displayName) task failed"
        case .checksFailed: head = "Checks failed"
        }
        return hidden || task.title.isEmpty ? head : "\(head): \(task.title)"
    }
}

/// Compares each source's list with the last one. A source's first list is only remembered,
/// so turning the feature on doesn't announce everything that already happened.
public struct CloudChanges: Sendable {
    private struct Seen: Sendable {
        /// Nil when the status was a guess, which is never compared against.
        var status: CloudStatus?
        /// Nil when the checks' last state isn't known (checks were just turned on).
        var failing: Bool?
    }

    private var seen: [CloudSource: [String: Seen]] = [:]

    public init() {}

    /// Forgets a source, for when it's turned off or its login changes.
    public mutating func forget(_ source: CloudSource) { seen[source] = nil }

    /// Forgets every pull request's checks, so turning checks on doesn't announce ones already red.
    public mutating func forgetChecks() {
        for source in seen.keys {
            seen[source] = seen[source]?.mapValues { Seen(status: $0.status, failing: nil) }
        }
    }

    /// Events only for tasks updated within `CloudLane.recentWindow` of `now`, so an old task
    /// that turns up again stays quiet.
    public mutating func update(source: CloudSource, tasks: [CloudTask], now: Date) -> [CloudEvent] {
        let before = seen[source]
        seen[source] = Dictionary(
            tasks.map {
                ($0.id, Seen(status: $0.statusKnown ? $0.status : nil, failing: $0.checks?.state == .failing))
            },
            uniquingKeysWith: { first, _ in first })
        guard let before else { return [] }
        var events: [CloudEvent] = []
        for task in tasks where now.timeIntervalSince(task.updatedAt) < CloudLane.recentWindow {
            let old = before[task.id]
            let comparable = old.map { $0.status != nil } ?? true
            if task.statusKnown, comparable, old?.status != task.status {
                switch task.status {
                case .ready: events.append(CloudEvent(kind: .finished, task: task))
                case .failed: events.append(CloudEvent(kind: .failed, task: task))
                default: break
                }
            }
            if task.checks?.state == .failing, old.map({ $0.failing == false }) ?? true {
                events.append(CloudEvent(kind: .checksFailed, task: task))
            }
        }
        return events
    }
}

/// What the Cloud lane shows and which tasks need more reading.
public enum CloudLane {
    /// Finished tasks stay this long.
    public static let recentWindow: TimeInterval = 24 * 3600
    public static let limit = 6
    /// Pull requests whose checks are read each look, at most.
    public static let checksLimit = 5
    /// Cursor runs read each look, at most.
    public static let cursorRunLimit = 5

    /// Working tasks first, then the newest of the rest from the last day.
    public static func visible(_ tasks: [CloudTask], now: Date) -> [CloudTask] {
        let shown = tasks.filter { $0.status.inFlight || now.timeIntervalSince($0.updatedAt) < recentWindow }
        let sorted = shown.sorted { lhs, rhs in
            if lhs.status.inFlight != rhs.status.inFlight { return lhs.status.inFlight }
            return lhs.updatedAt > rhs.updatedAt
        }
        return Array(sorted.prefix(limit))
    }

    /// Recent tasks with an open GitHub pull request.
    public static func needingChecks(_ tasks: [CloudTask], now: Date) -> [CloudTask] {
        let wanted = tasks.filter {
            $0.status != .cancelled && $0.pullRequestOpen && CloudParse.isGitHubPullRequest($0.pullRequest)
                && now.timeIntervalSince($0.updatedAt) < recentWindow
        }
        return Array(wanted.sorted { $0.updatedAt > $1.updatedAt }.prefix(checksLimit))
    }

    /// Agents whose latest run is worth reading: active ones, and ones that changed since their
    /// run was last read. `fetched` holds each agent's `updatedAt` at that read.
    public static func cursorRunsToFetch(_ agents: [CursorAgent], fetched: [String: Date]) -> [String] {
        let wanted = agents.filter { agent in
            agent.latestRunID != nil && (agent.active || fetched[agent.id] != agent.updatedAt)
        }
        return Array(wanted.prefix(cursorRunLimit).map(\.id))
    }
}
