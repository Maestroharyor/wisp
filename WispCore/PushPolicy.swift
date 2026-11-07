import Foundation

/// What can be sent to the phone, each with its own switch in Settings › Phone.
public enum PushKind: String, CaseIterable, Sendable {
    case approval
    case needsYou
    case done
    case limit
    case budget
    /// Cloud agent tasks that finished or failed, and pull requests whose checks failed.
    case cloud

    public var title: String {
        switch self {
        case .approval: "Permission requests"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .limit: "Usage limits"
        case .budget: "Daily budget"
        case .cloud: "Cloud tasks"
        }
    }

    /// On when push is first turned on: the moments that need the user. Done can be chatty.
    /// Cloud tasks only send while Cloud agents is on, which is off by default.
    public static let defaults: Set<PushKind> = [.approval, .needsYou, .limit, .budget, .cloud]
}

/// When pushes go out.
public enum PushMode: String, CaseIterable, Sendable {
    /// The screen is locked or the Mac has been idle a while.
    case away
    case always

    public static let `default` = PushMode.away

    public var title: String {
        switch self {
        case .away: "When I'm away"
        case .always: "Always"
        }
    }
}

/// Decides whether a moment goes to the phone: its kind is on, the user is away (or the mode
/// is Always), and it isn't a repeat. Approvals go once each; other moments at most once a
/// minute per session or text, and no more than `hourlyCap` an hour between them, to stay well
/// inside a public server's daily limit.
public struct PushPolicy: Sendable {
    public var kinds: Set<PushKind>
    public var mode: PushMode
    public var idleMinutes: Int

    public static let defaultIdleMinutes = 2
    public static let idleMinutesRange = 1...30
    /// The same moment for the same session is sent at most once in this many seconds.
    static let repeatInterval: TimeInterval = 60
    /// Moments other than approvals sent in the last hour, at most.
    static let hourlyCap = 20
    /// Approval ids remembered so none is sent twice; old ones drop off.
    static let approvalMemory = 200

    private var lastSent: [String: Date] = [:]
    private var sentApprovals: [String] = []
    private var recent: [Date] = []

    public init(kinds: Set<PushKind> = PushKind.defaults, mode: PushMode = .default, idleMinutes: Int = 2) {
        self.kinds = kinds
        self.mode = mode
        self.idleMinutes = idleMinutes
    }

    /// Away means locked, or no keyboard, mouse or trackpad input for `idleMinutes`.
    public static func isAway(locked: Bool, idleSeconds: TimeInterval, idleMinutes: Int) -> Bool {
        locked || idleSeconds >= TimeInterval(max(idleMinutes, 1) * 60)
    }

    /// Whether the mode lets anything out right now.
    public func inMode(away: Bool) -> Bool { mode == .always || away }

    /// Whether an approval was already sent.
    public func sent(approval id: String) -> Bool { sentApprovals.contains(id) }

    /// Records and allows the push when it should go. `key` tells moments apart: the approval's
    /// id, the session for Needs you and Done, the text for limits and budget.
    public mutating func allow(_ kind: PushKind, key: String, away: Bool, now: Date) -> Bool {
        guard kinds.contains(kind), inMode(away: away) else { return false }
        if kind == .approval {
            guard !sentApprovals.contains(key) else { return false }
            sentApprovals.append(key)
            if sentApprovals.count > Self.approvalMemory { sentApprovals.removeFirst() }
            return true
        }
        let id = kind.rawValue + "|" + key
        if let last = lastSent[id], now.timeIntervalSince(last) < Self.repeatInterval { return false }
        recent = recent.filter { now.timeIntervalSince($0) < 3600 }
        guard recent.count < Self.hourlyCap else { return false }
        recent.append(now)
        lastSent = lastSent.filter { now.timeIntervalSince($0.value) < Self.repeatInterval }
        lastSent[id] = now
        return true
    }
}

/// Something about the agents worth telling the user away from the Mac. Approvals are followed
/// through the hub's queue instead, since they need a reply.
public enum AgentMoment: Equatable, Sendable {
    case needsYou(session: String, project: String, source: AgentSource)
    case done(session: String, project: String, source: AgentSource)
    /// Wisp's own notice text for a usage window or the daily budget.
    case limit(String)
    case budget(String)
    case cloud(CloudEvent)

    public var kind: PushKind {
        switch self {
        case .needsYou: .needsYou
        case .done: .done
        case .limit: .limit
        case .budget: .budget
        case .cloud: .cloud
        }
    }

    /// Tells repeats apart for `PushPolicy`: per session, or per text.
    public var key: String {
        switch self {
        case .needsYou(let session, _, _), .done(let session, _, _): session
        case .limit(let text), .budget(let text): text
        case .cloud(let event): event.kind.rawValue + "|" + event.task.id
        }
    }

    /// The notification, masked as `PushMessage` describes.
    public func notice(hidden: Bool) -> PushNotice {
        switch self {
        case .needsYou(_, let project, let source):
            PushMessage.needsYou(agent: source.displayName, project: project, hidden: hidden)
        case .done(_, let project, let source):
            PushMessage.done(agent: source.displayName, project: project, hidden: hidden)
        case .limit(let text): PushMessage.limit(text)
        case .budget(let text): PushMessage.budget(text)
        case .cloud(let event): PushMessage.cloud(event, hidden: hidden)
        }
    }
}
