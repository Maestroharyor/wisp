import Foundation

/// The user's last prompt, made fit for one line of a session row. It stays in memory only:
/// never logged, saved or sent.
public enum PromptText {
    /// Characters kept, "…" included.
    public static let limit = 120
    /// Only this much is looked at, so a pasted file doesn't run through the masks.
    static let readLimit = 1000

    /// One line with runs of whitespace collapsed, likely secrets masked and the length
    /// capped; nil when there's no text.
    public static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.prefix(readLimit).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let text = ToolLabel.mask(words.joined(separator: " "))
        return text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}

/// What a session row in the Agents widget shows under its title: what you last asked, what
/// it's doing now and for how long.
public struct SessionGlance: Equatable, Sendable {
    public enum Activity: Equatable, Sendable {
        case tool(ToolDescription)
        case compacting
        case working
        case approval
        case waiting
        case done
        case ready

        public var text: String {
            switch self {
            case .tool(let tool): tool.label
            case .compacting: "Compacting context"
            case .working: "Working"
            case .approval: "Waiting for approval"
            case .waiting: "Needs your input"
            case .done: "Done, click to jump"
            case .ready: "Ready"
            }
        }
    }

    /// "You: <last prompt>"; nil when the agent sent none or details are hidden.
    public let prompt: String?
    public let activity: Activity
    /// The agent's name, for its tag.
    public let agent: String
    /// How long the session has been in its state ("27m").
    public let age: String

    public static func make(_ session: AgentSession, now: Date, hidden: Bool) -> SessionGlance {
        SessionGlance(
            prompt: hidden ? nil : session.lastPrompt.map { "You: \($0)" },
            activity: activity(session, now: now, hidden: hidden),
            agent: session.source.displayName,
            age: age(now.timeIntervalSince(session.stateSince ?? session.turnStarted)))
    }

    private static func activity(_ session: AgentSession, now: Date, hidden: Bool) -> Activity {
        if session.compacting { return .compacting }
        switch session.state {
        case .running:
            return session.pillTool(now: now).map { .tool($0.description(hidden: hidden)) } ?? .working
        case .needsApproval: return .approval
        case .waiting: return .waiting
        case .finished: return .done
        case .idle: return .ready
        }
    }

    /// "now", "27m", "3h" or "2d".
    public static func age(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }
}

/// One usage window for the header over the sessions list: "5 h 42%", resetting in "2h 10m".
public struct LimitSummary: Equatable, Sendable {
    /// The window, with the agent's name for anyone but Claude Code ("Codex 5 h").
    public let label: String
    public let percent: Int
    /// Time left until the window starts over; nil when it isn't known.
    public let resetsIn: String?

    /// The windows still current, in the order given. One past its reset time is stale.
    public static func make(_ readings: [UsageReading], now: Date) -> [LimitSummary] {
        readings.filter { $0.resets.map { $0 > now } ?? true }.map { reading in
            let agent = reading.source == .claude ? "" : reading.source.displayName + " "
            return LimitSummary(
                label: agent + reading.window.shortName,
                percent: Int(min(max(reading.percent, 0), 100).rounded()),
                resetsIn: reading.resets.map { remaining($0.timeIntervalSince(now)) })
        }
    }

    /// "12m", "3h 5m" or "3d 4h", rounded up to the minute so it never reads 0m.
    public static func remaining(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        let (days, hours, mins) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
        return "\(mins)m"
    }
}

extension LimitWindow {
    /// "5 h" or "7 d".
    public var shortName: String {
        switch self {
        case .fiveHour: "5 h"
        case .sevenDay: "7 d"
        }
    }
}

/// The few changed lines an approval card shows before you open the full preview, with the
/// whole change's "+N −M".
public struct InlineDiff: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let kind: DiffLine.Kind
        public let text: String
        /// The line in the file, when the request says (a new file's lines are numbered from 1).
        public let number: Int?
    }

    public let added: Int
    public let removed: Int
    public let lines: [Line]
    /// A Write: the file's whole new content, which may replace lines the request doesn't show.
    public let wholeFile: Bool

    public static let maxLines = 3
    /// Characters kept of a line; the card truncates anyway.
    public static let lineLimit = 160

    /// "+4 −2", or "12 lines" for a file's whole content.
    public var counts: String {
        wholeFile ? "\(added) \(added == 1 ? "line" : "lines")" : "+\(added) −\(removed)"
    }

    /// The diff for an edit, a new file or a Codex patch; nil for anything else or when
    /// nothing changes.
    public static func make(tool: String, input: JSONValue?, maxLines: Int = maxLines) -> InlineDiff? {
        switch tool {
        case "Edit":
            return edits([input], maxLines: maxLines)
        case "MultiEdit":
            guard case .array(let edits) = input?["edits"] else { return nil }
            return self.edits(edits, maxLines: maxLines)
        case "Write":
            guard let content = input?["content"]?.stringValue,
                !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            // Counted in bytes without splitting, since a new file can be large. Swift reads "\r\n"
            // as one character, so lines split on either.
            let newline = UInt8(ascii: "\n")
            let newlines = content.utf8.reduce(0) { $0 + ($1 == newline ? 1 : 0) }
            let count = newlines + (content.utf8.last == newline ? 0 : 1)
            let shown = content.split(
                maxSplits: maxLines, omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }
            )
            .prefix(min(maxLines, count)).enumerated()
            .map { Line(kind: .added, text: cut(String($0.element)), number: $0.offset + 1) }
            return InlineDiff(added: count, removed: 0, lines: Array(shown), wholeFile: true)
        case "apply_patch":
            guard let patch = input?["command"]?.stringValue else { return nil }
            return self.patch(patch, maxLines: maxLines)
        default:
            return nil
        }
    }

    /// The changed file's name without its folders, for private mode, where the card shows that
    /// and the counts but no lines. A patch touching several files names the first and counts
    /// the rest ("a.py +1"). Nil for anything that isn't a file change.
    public static func fileName(tool: String, input: JSONValue?) -> String? {
        switch tool {
        case "Edit", "MultiEdit", "Write":
            return input?["file_path"]?.stringValue.flatMap(lastComponent)
        case "apply_patch":
            let headers = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
            let files = (input?["command"]?.stringValue ?? "").components(separatedBy: "\n").compactMap { line in
                headers.first(where: line.hasPrefix).map { String(line.dropFirst($0.count)) }
            }
            guard let first = files.first.flatMap(lastComponent) else { return nil }
            return files.count > 1 ? "\(first) +\(files.count - 1)" : first
        default:
            return nil
        }
    }

    private static func lastComponent(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespaces)).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    private static func edits(_ edits: [JSONValue?], maxLines: Int) -> InlineDiff? {
        var removed: [String] = []
        var added: [String] = []
        for edit in edits {
            guard let old = edit?["old_string"]?.stringValue, let new = edit?["new_string"]?.stringValue else {
                continue
            }
            let changes = LineDiff.changes(old: LineDiff.lines(old), new: LineDiff.lines(new))
            removed += changes.removed
            added += changes.added
        }
        return summary(removed: removed, added: added, maxLines: maxLines)
    }

    /// Codex's patch format: "-" and "+" lines under "*** Update File:" headers, no line numbers.
    private static func patch(_ patch: String, maxLines: Int) -> InlineDiff? {
        let lines = ApprovalPreview.patchLines(patch)
        return summary(
            removed: lines.filter { $0.kind == .removed }.map(\.text),
            added: lines.filter { $0.kind == .added }.map(\.text), maxLines: maxLines)
    }

    /// Up to `maxLines`, removed lines first: both sides show when both have lines, and
    /// one side fills what the other doesn't need.
    private static func summary(removed: [String], added: [String], maxLines: Int) -> InlineDiff? {
        guard !removed.isEmpty || !added.isEmpty else { return nil }
        let removedTake = min(removed.count, maxLines - min(added.count, maxLines / 2))
        let addedTake = min(added.count, maxLines - removedTake)
        let lines =
            removed.prefix(removedTake).map { Line(kind: .removed, text: cut($0), number: nil) }
            + added.prefix(addedTake).map { Line(kind: .added, text: cut($0), number: nil) }
        return InlineDiff(added: added.count, removed: removed.count, lines: lines, wholeFile: false)
    }

    private static func cut(_ text: String) -> String {
        let line = text.hasSuffix("\r") ? String(text.dropLast()) : text
        return String(line.replacingOccurrences(of: "\t", with: "    ").prefix(lineLimit))
    }
}

extension ApprovalKeys {
    /// The shortcut that does `action` on a card, as the hint beside its button: "⇪ Y" with
    /// Hyper, "⌃⌥⌘Y" with the fallback. Nil for an option past 9, which has no key.
    public static func hint(_ action: Action, hyper: Bool) -> String? {
        let key: UInt16
        switch action {
        case .allow, .send: key = yes
        case .deny: key = no
        case .pick(let index):
            guard digits.indices.contains(index) else { return nil }
            key = digits[index]
        }
        return Hotkey(keyCode: key, modifiers: hyper ? .hyper : fallbackModifiers).description
    }
}
