import Foundation

/// What Wisp knows about the moment, for choosing a profile.
public struct ContextState: Equatable, Sendable {
    public var frontApp: String?
    public var mediaPlaying: Bool
    public var focus: String?
    public var agentWaiting: Bool
    public var externalDisplay: Bool

    public init(
        frontApp: String? = nil, mediaPlaying: Bool = false, focus: String? = nil, agentWaiting: Bool = false,
        externalDisplay: Bool = false
    ) {
        self.frontApp = frontApp
        self.mediaPlaying = mediaPlaying
        self.focus = focus
        self.agentWaiting = agentWaiting
        self.externalDisplay = externalDisplay
    }
}

public enum ContextTrigger: Codable, Equatable, Sendable {
    /// Any of these bundle identifiers is frontmost.
    case frontApp([String])
    case mediaPlaying
    /// A macOS Focus with this name is on.
    case focus(String)
    case agentWaiting
    case externalDisplay

    public func matches(_ state: ContextState) -> Bool {
        switch self {
        case .frontApp(let ids): state.frontApp.map(ids.contains) ?? false
        case .mediaPlaying: state.mediaPlaying
        case .focus(let name): state.focus == name
        case .agentWaiting: state.agentWaiting
        case .externalDisplay: state.externalDisplay
        }
    }
}

public struct ContextRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var trigger: ContextTrigger
    public var profile: String
    public var priority: Int
    public var enabled: Bool

    public init(id: String, trigger: ContextTrigger, profile: String, priority: Int, enabled: Bool) {
        self.id = id
        self.trigger = trigger
        self.profile = profile
        self.priority = priority
        self.enabled = enabled
    }
}

public enum ContextRules {
    /// The profile of the highest-priority enabled rule that matches, if any.
    public static func match(_ rules: [ContextRule], state: ContextState) -> String? {
        matchingRule(rules, state: state)?.profile
    }

    /// The highest-priority enabled rule that matches, if any.
    public static func matchingRule(_ rules: [ContextRule], state: ContextState) -> ContextRule? {
        rules.filter { $0.enabled && $0.trigger.matches(state) }.max { $0.priority < $1.priority }
    }

    /// Automatic switches change the start page and surface only. A Focus is a deliberate
    /// choice the user made, so a Focus rule may also swap the Home widgets.
    public static func swapsHome(_ rule: ContextRule?) -> Bool {
        guard case .focus = rule?.trigger else { return false }
        return true
    }

    /// Rules Wisp starts with; each can be switched off.
    public static let defaults: [ContextRule] = [
        ContextRule(
            id: "coding",
            trigger: .frontApp([
                "com.apple.dt.Xcode", "com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2",
                "com.microsoft.VSCode", "dev.warp.Warp-Stable", "com.todesktop.230313mzl4w4u92",
            ]),
            profile: "Code", priority: 2, enabled: true),
        ContextRule(id: "agent", trigger: .agentWaiting, profile: "Code", priority: 4, enabled: true),
        ContextRule(id: "music", trigger: .mediaPlaying, profile: "Music", priority: 1, enabled: true),
        ContextRule(id: "work-focus", trigger: .focus("Work"), profile: "Work", priority: 3, enabled: true),
    ]
}

/// Turns a stream of rule matches into profile switches: a manual choice holds for a
/// while, and a new match must stay put for `debounce` seconds before it applies.
public struct ContextEngineState: Sendable {
    public static let baseProfile = "Everyday"

    public private(set) var active = ContextEngineState.baseProfile
    private let debounce: TimeInterval
    private let manualHold: TimeInterval
    private var heldUntil: Date?
    private var pending: (profile: String, since: Date)?

    public init(debounce: TimeInterval, manualHold: TimeInterval, active: String = ContextEngineState.baseProfile) {
        self.active = active
        self.debounce = debounce
        self.manualHold = manualHold
    }

    /// A new profile is waiting out the debounce.
    public var isPending: Bool { pending != nil }

    public mutating func chooseManually(_ profile: String, at date: Date) {
        active = profile
        heldUntil = date.addingTimeInterval(manualHold)
        pending = nil
    }

    /// Returns the profile to switch to now, or nil to stay.
    public mutating func propose(_ candidate: String?, at date: Date) -> String? {
        if let heldUntil, date < heldUntil {
            pending = nil
            return nil
        }
        heldUntil = nil
        let target = candidate ?? Self.baseProfile
        guard target != active else {
            pending = nil
            return nil
        }
        if pending?.profile != target {
            pending = (target, date)
        }
        guard let pending, date.timeIntervalSince(pending.since) >= debounce else { return nil }
        active = target
        self.pending = nil
        return target
    }
}
