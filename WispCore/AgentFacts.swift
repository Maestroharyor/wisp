import Foundation

/// One labelled figure in a session's details.
public struct AgentFact: Equatable, Sendable, Identifiable {
    public let label: String
    public let value: String

    public var id: String { label }

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

extension AgentSession {
    /// Everything known about the session, most useful first. Facts nobody reported are
    /// left out, so a session without Claude Code's status bar shows fewer.
    public func facts(now: Date) -> [AgentFact] {
        var result: [AgentFact] = []
        let live = extras
        if let name = live.sessionName, !name.isEmpty { result.append(AgentFact("Name", name)) }
        if let model = displayModel {
            var detail = [model]
            if let effort = live.effort { detail.append("\(effort) effort") }
            if live.thinking == true { detail.append("thinking") }
            if live.fastMode == true { detail.append("fast") }
            result.append(AgentFact("Model", detail.joined(separator: " · ")))
        }
        if let percent = contextPercent {
            var text = "\(Int(percent.rounded()))%"
            if let tokens = live.contextTokens, let size = contextSize {
                text += " · \(Self.count(tokens)) of \(Self.count(size))"
            }
            result.append(AgentFact("Context", text))
        }
        if let cost { result.append(AgentFact("Cost", (costIsReal ? "" : "~") + String(format: "$%.2f", cost))) }
        if let usage {
            result.append(
                AgentFact(
                    "Tokens",
                    "\(Self.count(usage.input)) in · \(Self.count(usage.output)) out · "
                        + "\(Self.count(usage.cacheRead)) cache read · \(Self.count(usage.cacheWrite)) cache write"))
        } else if let input = live.inputTokens, let output = live.outputTokens {
            result.append(AgentFact("Tokens", "\(Self.count(input)) in · \(Self.count(output)) out"))
        }
        if linesAdded > 0 || linesRemoved > 0 { result.append(AgentFact("Lines", "+\(linesAdded) −\(linesRemoved)")) }
        if let took = lastTurnDuration { result.append(AgentFact("Last turn", Self.time(took))) }
        if let duration {
            var text = Self.time(duration)
            if let apiDuration { text += " · \(Self.time(apiDuration)) waiting on the model" }
            result.append(AgentFact("Duration", text))
        }
        if let branch {
            var text = branch
            if let number = live.pullRequest {
                text +=
                    " · PR #\(number)"
                    + (live.pullRequestState.map { " (\($0.replacingOccurrences(of: "_", with: " ")))" } ?? "")
            }
            result.append(AgentFact("Branch", text))
        }
        if let ratio = live.cacheHitRatio { result.append(AgentFact("Cache hits", "\(Int((ratio * 100).rounded()))%")) }
        if live.fiveHourPercent != nil || live.sevenDayPercent != nil {
            let parts = [
                live.fiveHourPercent.map { "\(Int($0.rounded()))% of 5 h" },
                live.sevenDayPercent.map { "\(Int($0.rounded()))% of 7 days" },
            ].compactMap { $0 }
            result.append(AgentFact("Usage limits", parts.joined(separator: " · ")))
        }
        if let style = live.outputStyle, style != "default" { result.append(AgentFact("Output style", style)) }
        if autoApprove { result.append(AgentFact("Approvals", "Allow All is on")) }
        if !cwd.isEmpty { result.append(AgentFact("Folder", cwd)) }
        var agent = source.displayName
        if let version = live.version { agent += " \(version)" }
        result.append(AgentFact("Agent", agent))
        result.append(AgentFact("Last activity", Self.ago(now.timeIntervalSince(updated))))
        result.append(AgentFact("Session ID", id))
        return result
    }

    static func count(_ value: Int) -> String { TokenUsage.compact(value) }

    /// "45s", "4m 12s", "1h 03m".
    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(String(format: "%02d", total % 60))s" }
        return "\(total / 3600)h \(String(format: "%02d", total % 3600 / 60))m"
    }

    static func ago(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "just now" : "\(time(seconds)) ago"
    }
}
