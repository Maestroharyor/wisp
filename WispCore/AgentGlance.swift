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

/// What a session row in the Agents widget shows: its task, what you last asked, what it's doing
/// now and how long it has run.
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
    /// How long the session has run since it started ("1h").
    public let runTime: String
    /// What the session is about, for its row's title beside the project: its name, else the
    /// AI summary, else its first prompt. Nil when none is known or details are hidden.
    public let title: String?
    /// Permission prompts are skipped, so the row shows a red Bypass.
    public let bypass: Bool

    /// Characters kept of a title, "…" included.
    public static let titleLimit = 60

    /// `summary` is the on-device AI's summary of the session's last turn, when there is one.
    public static func make(_ session: AgentSession, now: Date, hidden: Bool, summary: String? = nil) -> SessionGlance {
        SessionGlance(
            prompt: hidden ? nil : session.lastPrompt.map { "You: \($0)" },
            activity: activity(session, now: now, hidden: hidden),
            agent: session.source.displayName,
            runTime: age(now.timeIntervalSince(session.started ?? session.turnStarted)),
            title: hidden ? nil : title(session, summary: summary),
            bypass: session.bypassesPermissions)
    }

    private static func title(_ session: AgentSession, summary: String?) -> String? {
        let name = session.extras.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = summary.map(SessionSummaryText.firstSentence)
        let text = [name, sentence, session.firstPrompt].lazy.compactMap { $0 }.first { !$0.isEmpty }
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count <= titleLimit ? line : String(line.prefix(titleLimit - 1)) + "…"
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

/// The first rows of a change that an approval card shows before you open the full preview:
/// changed lines in order with a line of context around them, and the whole change's "+N −M".
public struct InlineDiff: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let kind: DiffLine.Kind
        public let text: String
        /// The line's number on each side, counted from 1 within the edit (a new file's are its
        /// real lines); nil on a side that doesn't have it and for patches.
        public let old: Int?
        public let new: Int?

        public init(kind: DiffLine.Kind, text: String, old: Int? = nil, new: Int? = nil) {
            self.kind = kind
            self.text = text
            self.old = old
            self.new = new
        }
    }

    public let added: Int
    public let removed: Int
    public let lines: [Line]
    /// A Write: the file's whole new content, which may replace lines the request doesn't show.
    public let wholeFile: Bool

    public static let maxLines = 6
    /// Unchanged lines kept around each change.
    public static let contextLines = 1
    /// Characters kept of a line; the card truncates anyway.
    public static let lineLimit = 160

    /// "+4 −2", or "12 lines" for a file's whole content.
    public var counts: String {
        wholeFile ? "\(added) \(added == 1 ? "line" : "lines")" : "+\(added) −\(removed)"
    }

    /// The gutter's numbers for `line`: a new file's as they are, an edit's moved to where it
    /// starts in the file (`anchor`, from `FileAnchor`). Nil without an anchor, so nothing is
    /// numbered from a guess.
    public func numbers(for line: Line, anchor: Int?) -> (old: Int?, new: Int?) {
        if wholeFile { return (line.old, line.new) }
        return (FileAnchor.shift(line.old, anchor: anchor), FileAnchor.shift(line.new, anchor: anchor))
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
            .map { Line(kind: .added, text: cut(String($0.element)), new: $0.offset + 1) }
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
            let files = patchFiles(input)
            guard let first = files.first.flatMap(lastComponent) else { return nil }
            return files.count > 1 ? "\(first) +\(files.count - 1)" : first
        default:
            return nil
        }
    }

    /// The file a change is to, as the request names it: an edit's or a new file's path, a
    /// patch's first file. Nil for anything that isn't a file change.
    public static func filePath(tool: String, input: JSONValue?) -> String? {
        switch tool {
        case "Edit", "MultiEdit", "Write":
            return input?["file_path"]?.stringValue
        case "apply_patch":
            return patchFiles(input).first
        default:
            return nil
        }
    }

    private static func patchFiles(_ input: JSONValue?) -> [String] {
        let headers = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        return (input?["command"]?.stringValue ?? "").components(separatedBy: "\n").compactMap { line in
            headers.first(where: line.hasPrefix).map { String(line.dropFirst($0.count)) }
        }
    }

    private static func lastComponent(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespaces)).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    /// Each edit's changes in place with `contextLines` around them; edits after the first follow
    /// a gap row, as they sit elsewhere in the file.
    private static func edits(_ edits: [JSONValue?], maxLines: Int) -> InlineDiff? {
        var rows: [DiffLine] = []
        for edit in edits {
            guard let old = edit?["old_string"]?.stringValue, let new = edit?["new_string"]?.stringValue else {
                continue
            }
            let lines = LineDiff.unified(old: LineDiff.lines(old), new: LineDiff.lines(new), context: contextLines)
            guard !lines.isEmpty else { continue }
            if !rows.isEmpty { rows.append(DiffLine(kind: .hunk, text: LineDiff.gap)) }
            rows += lines
        }
        return summary(rows, maxLines: maxLines)
    }

    /// Codex's patch format: "-", "+" and context lines under "*** Update File:" headers, with no
    /// line numbers. The headers are left out; the card's title names the file.
    private static func patch(_ patch: String, maxLines: Int) -> InlineDiff? {
        summary(ApprovalPreview.patchLines(patch).filter { $0.kind != .hunk }, maxLines: maxLines)
    }

    /// The first `maxLines` rows, with every change counted.
    private static func summary(_ rows: [DiffLine], maxLines: Int) -> InlineDiff? {
        let added = rows.filter { $0.kind == .added }.count
        let removed = rows.filter { $0.kind == .removed }.count
        guard added + removed > 0 else { return nil }
        let lines = rows.prefix(maxLines).map { Line(kind: $0.kind, text: cut($0.text), old: $0.old, new: $0.new) }
        return InlineDiff(added: added, removed: removed, lines: lines, wholeFile: false)
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
