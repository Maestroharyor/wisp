import Foundation

/// The timed alerts' limits and which are on. A limit is kept while its alert is off, so
/// what's already past it can be told apart from what isn't when the alert is turned on.
public struct AgentAlertRules: Equatable, Sendable {
    /// A single tool call running longer than this.
    public var toolMinutes: Int
    public var tools: Bool
    /// A session waiting for the user (Needs you or an approval) longer than this.
    public var nudgeMinutes: Int
    public var nudges: Bool

    public init(toolMinutes: Int = 5, tools: Bool = false, nudgeMinutes: Int = 3, nudges: Bool = false) {
        self.toolMinutes = toolMinutes
        self.tools = tools
        self.nudgeMinutes = nudgeMinutes
        self.nudges = nudges
    }
}

public enum AgentAlert: Equatable, Sendable {
    case longTool(session: String, project: String, tool: ActiveTool, minutes: Int)
    /// `approval` is true when the session waits on a permission request rather than a message.
    case nudge(session: String, project: String, approval: Bool)

    /// The notice for a long tool ("5m · npm test"): the pill's side has room for a few words,
    /// and the hourglass says why. Nil for a nudge, which shows the session in the pill instead.
    /// `hidden` keeps the tool's input out ("5m · Running").
    public func text(hidden: Bool) -> String? {
        guard case .longTool(_, _, let tool, let minutes) = self else { return nil }
        return "\(minutes)m · \(tool.description(hidden: hidden).short)"
    }

    /// One notice for every long tool in `alerts`: the notch has a single notice slot, so the
    /// first is named and the rest counted ("5m · npm test +1"). Nil when there are none.
    public static func notice(_ alerts: [AgentAlert], hidden: Bool) -> String? {
        let texts = alerts.compactMap { $0.text(hidden: hidden) }
        guard let first = texts.first else { return nil }
        return texts.count > 1 ? "\(first) +\(texts.count - 1)" : first
    }
}

/// Decides when a long tool call or a long wait gets its one alert. Nothing arrives from the
/// agent while a tool runs or a session waits, so the caller checks again at `nextCheck`.
public struct AgentAlerts: Equatable, Sendable {
    /// Tools and waits that already alerted (or were already over the limit when it was off).
    public private(set) var fired: Set<String> = []

    public init() {}

    /// What has gone over its limit since the last call. A rule that's off still marks what's
    /// over, so turning it on later doesn't alert about something long past.
    public mutating func due(_ sessions: [AgentSession], rules: AgentAlertRules, now: Date) -> [AgentAlert] {
        var alerts: [AgentAlert] = []
        var current: Set<String> = []
        for item in Self.items(sessions, rules: rules) {
            current.insert(item.key)
            guard !fired.contains(item.key), now >= item.start + item.limit else { continue }
            fired.insert(item.key)
            if let alert = item.alert { alerts.append(alert) }
        }
        // Finished tools and ended waits never come back, so their keys can go.
        fired.formIntersection(current)
        return alerts
    }

    /// The soonest a tool or wait not yet alerted goes over an active limit; nil when none will.
    public func nextCheck(_ sessions: [AgentSession], rules: AgentAlertRules, now: Date) -> Date? {
        Self.items(sessions, rules: rules)
            .filter { $0.alert != nil && !fired.contains($0.key) }
            .map { max(now, $0.start + $0.limit) }
            .min()
    }

    /// Something that can go over a limit. `alert` is nil while its rule is off, so it's
    /// marked without alerting once past the limit.
    private struct Item {
        let key: String
        let start: Date
        let limit: TimeInterval
        let alert: AgentAlert?
    }

    private static func items(_ sessions: [AgentSession], rules: AgentAlertRules) -> [Item] {
        var items: [Item] = []
        for session in sessions {
            for tool in session.runningTools {
                let key = "tool|\(session.id)|\(tool.id ?? String(tool.started.timeIntervalSince1970))"
                let alert =
                    rules.tools
                    ? AgentAlert.longTool(
                        session: session.id, project: session.project, tool: tool, minutes: rules.toolMinutes) : nil
                items.append(Item(key: key, start: tool.started, limit: seconds(rules.toolMinutes), alert: alert))
            }
            let waiting = session.state == .waiting || session.state == .needsApproval
            if waiting, let since = session.stateSince {
                let key = "wait|\(session.id)|\(since.timeIntervalSince1970)"
                let alert =
                    rules.nudges
                    ? AgentAlert.nudge(
                        session: session.id, project: session.project, approval: session.state == .needsApproval)
                    : nil
                items.append(Item(key: key, start: since, limit: seconds(rules.nudgeMinutes), alert: alert))
            }
        }
        return items
    }

    private static func seconds(_ minutes: Int) -> TimeInterval { TimeInterval(max(minutes, 0)) * 60 }
}
