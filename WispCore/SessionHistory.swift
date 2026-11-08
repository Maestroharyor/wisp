import Foundation

/// How a test command went, as far as hook events can tell. Hooks never carry the output, so
/// the outcome comes from which events arrived.
public enum TestOutcome: String, Codable, Sendable {
    case passed
    /// The call never reported success and wasn't waiting on a permission prompt: it failed or
    /// was stopped.
    case notPassed
    /// It ran, but the agent's hooks don't say whether it passed.
    case ran
    /// It asked for permission and never reported back: it may have been denied in the terminal.
    case unknown
}

public struct TestRun: Codable, Equatable, Sendable {
    /// Masked, first line only; "Tests" when it ran while details were hidden.
    public var command: String
    public var outcome: TestOutcome

    public init(command: String, outcome: TestOutcome) {
        self.command = command
        self.outcome = outcome
    }
}

/// One run of a coding-agent session, from its first event to its last turn or its end, built
/// from the hook events and figures Wisp already gets. Never holds prompts, messages, file
/// contents or command output. Commands are masked and cut to one line, and files are kept
/// relative to the project; both are left out of events that arrived while details were hidden.
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    /// The session id and when this run started, so a resumed session gets a new record.
    public var id: String
    public var sessionID: String
    public var project: String
    public var source: AgentSource
    public var branch: String?
    public var model: String?
    public var started: Date
    public var ended: Date
    /// The agent's own figure when it reports one, otherwise the time between first and last event.
    public var duration: TimeInterval
    public var turns: Int
    public var cost: Double?
    public var costIsReal: Bool
    public var tokens: Int?
    public var linesAdded: Int
    public var linesRemoved: Int
    public var toolCount: Int
    /// Calls per tool name.
    public var tools: [String: Int]
    /// Files edited or written, relative to the project folder (or just the name outside it).
    public var files: [String]
    public var commands: [String]
    public var tests: [TestRun]
    /// Permission requests and questions the agent asked.
    public var requests: Int
    public var questions: Int
    /// The session was waiting on the user when the record was last saved.
    public var endedWaiting: Bool
    /// The on-device AI's summary of this record, when AI is on.
    public var summary: String?

    public init(
        sessionID: String, project: String, source: AgentSource, started: Date, ended: Date? = nil,
        duration: TimeInterval = 0, turns: Int = 0, branch: String? = nil, model: String? = nil, cost: Double? = nil,
        costIsReal: Bool = false, tokens: Int? = nil, linesAdded: Int = 0, linesRemoved: Int = 0, toolCount: Int = 0,
        tools: [String: Int] = [:], files: [String] = [], commands: [String] = [], tests: [TestRun] = [],
        requests: Int = 0, questions: Int = 0, endedWaiting: Bool = false, summary: String? = nil
    ) {
        self.id = Self.id(session: sessionID, started: started)
        self.sessionID = sessionID
        self.project = project
        self.source = source
        self.branch = branch
        self.model = model
        self.started = started
        self.ended = ended ?? started
        self.duration = duration
        self.turns = turns
        self.cost = cost
        self.costIsReal = costIsReal
        self.tokens = tokens
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.toolCount = toolCount
        self.tools = tools
        self.files = files
        self.commands = commands
        self.tests = tests
        self.requests = requests
        self.questions = questions
        self.endedWaiting = endedWaiting
        self.summary = summary
    }

    static func id(session: String, started: Date) -> String {
        "\(session)@\(Int(started.timeIntervalSince1970))"
    }

    /// Nothing happened worth keeping: no prompt, no tool, no spend.
    public var isEmpty: Bool { turns == 0 && toolCount == 0 && (cost ?? 0) == 0 }

    /// Tool names by how often they ran, most first.
    public var toolsByUse: [(name: String, count: Int)] {
        tools.map { (name: $0.key, count: $0.value) }.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name
        }
    }

    /// What the on-device model is given: facts only, one per line. With `hidden`, files and
    /// commands stay out, so the summary is safe to show while details are hidden.
    public func summaryInput(hidden: Bool) -> String {
        var lines = ["Project: \(project)" + (branch.map { " (branch \($0))" } ?? "")]
        lines.append("Agent: \(source.displayName)" + (model.map { ", model \($0)" } ?? ""))
        lines.append("Length: \(DurationText.text(for: duration)), \(turns) prompt\(turns == 1 ? "" : "s")")
        if let cost { lines.append(String(format: "Cost: %@$%.2f", costIsReal ? "" : "~", cost)) }
        if linesAdded > 0 || linesRemoved > 0 { lines.append("Lines changed: +\(linesAdded) -\(linesRemoved)") }
        if !tools.isEmpty {
            lines.append("Tool calls: " + toolsByUse.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
        }
        if !hidden {
            if !files.isEmpty { lines.append("Files changed: " + files.joined(separator: ", ")) }
            if !commands.isEmpty { lines.append("Commands run: " + commands.joined(separator: "; ")) }
        }
        if !tests.isEmpty {
            let runs = tests.map { run in
                let command = hidden ? "Tests" : run.command
                return "\(command) \(run.outcome.phrase)"
            }
            lines.append("Tests: " + runs.joined(separator: "; "))
        }
        if requests > 0 { lines.append("Permission requests: \(requests)") }
        if questions > 0 { lines.append("Questions asked: \(questions)") }
        if endedWaiting { lines.append("Waiting for the user at the end: yes") }
        return lines.joined(separator: "\n")
    }

    /// Whether `query` matches what can be seen: project, agent, branch, model, tools, and
    /// (unless hidden) files, commands and the summary.
    public func matches(_ query: String, hidden: Bool) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        var fields = [project, source.displayName, branch ?? "", model ?? ""] + tools.keys
        if !hidden { fields += files + commands + tests.map(\.command) + [summary ?? ""] }
        let haystack = fields.joined(separator: "\n").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

extension TestOutcome {
    /// For the AI's record and the history list.
    public var phrase: String {
        switch self {
        case .passed: "passed"
        case .notPassed: "failed or stopped"
        case .ran: "ran"
        case .unknown: "result unknown"
        }
    }
}

/// Builds `SessionRecord`s from hook events as they arrive. The figures (cost, tokens, lines,
/// model) come from the live session when a record is taken, less what it already had when the
/// run began, so a resumed run doesn't repeat earlier spend.
///
/// Tools, files, commands and tests come from tool hooks: Wisp's tool activity hooks (Settings ›
/// Agents, off by default) and Copilot CLI's PostToolUse, which is always installed.
public struct SessionRecorder: Sendable {
    /// A figure the live session reports and a record counts from the run's start.
    enum Figure: CaseIterable, Sendable {
        case cost, tokens, linesAdded, linesRemoved, toolCount, duration

        func read(_ session: AgentSession) -> Double? {
            switch self {
            case .cost: session.cost
            case .tokens: session.usage.map { Double($0.all) }
            case .linesAdded: Double(session.linesAdded)
            case .linesRemoved: Double(session.linesRemoved)
            case .toolCount: Double(session.toolCount)
            case .duration: session.duration
            }
        }
    }

    /// The live session's figures when a draft starts. Wisp's session keeps its old figures on a
    /// resume, but the agent reports from zero, so the first reading that differs decides: below
    /// the start means the counter started over (the start becomes 0), above it means it went on.
    /// Either way the figure is settled for the rest of the run.
    struct Baseline: Sendable, Equatable {
        var start: [Figure: Double] = [:]
        var settled: Set<Figure> = []

        init(_ session: AgentSession?) {
            for figure in Figure.allCases { start[figure] = session.flatMap(figure.read) ?? 0 }
        }

        mutating func watch(_ session: AgentSession) {
            for figure in Figure.allCases where !settled.contains(figure) {
                guard let now = figure.read(session), let base = start[figure], now != base else { continue }
                if now < base { start[figure] = 0 }
                settled.insert(figure)
            }
        }

        /// The figure's part in this run; `watch` should have seen the session first.
        func delta(_ figure: Figure, _ now: Double) -> Double {
            max(0, now - (start[figure] ?? 0))
        }
    }

    struct PendingTest: Sendable {
        /// The tool use id, or the masked command without one.
        var key: String
        /// The masked command, in memory only, to pair a permission request or a denial.
        var match: String
        /// What's stored: the masked command, or "Tests" while details were hidden.
        var shown: String
        /// A permission request was seen for it.
        var asked = false
    }

    struct Draft: Sendable {
        var started: Date
        var baseline: Baseline
        var turns = 0
        var tools: [String: Int] = [:]
        var files: [String] = []
        var commands: [String] = []
        var tests: [TestRun] = []
        var pendingTests: [PendingTest] = []
        /// PreToolUse calls without their PostToolUse yet, per tool name, so a PostToolUse that
        /// had no PreToolUse (Copilot without tool activity, Cursor) is counted once.
        var openTools: [String: Int] = [:]
        var requests = 0
        var questions = 0
    }

    /// How a session began that starts a new run. A compaction keeps the run going.
    static let newRunSources: Set<String> = ["resume", "clear"]

    private var drafts: [String: Draft] = [:]

    public static let fileLimit = 40
    public static let commandLimit = 30
    public static let testLimit = 20
    /// Characters a stored command keeps.
    public static let commandLength = 120

    public init() {}

    /// `keepDetails` is false while agent details are hidden: commands and files from such
    /// events are never stored. `session` is the live session as it was before this event; a
    /// new draft takes its figures as the baseline.
    public mutating func observe(_ event: AgentEvent, at date: Date, keepDetails: Bool, session: AgentSession?) {
        let id = event.sessionID
        if event.kind == .sessionStart, let source = event.startSource, Self.newRunSources.contains(source) {
            // The run so far was recorded at its last stop.
            drafts[id] = nil
        }
        var draft = drafts[id] ?? Draft(started: date, baseline: Baseline(session))
        defer { drafts[id] = draft }
        switch event.kind {
        case .userPromptSubmit:
            draft.turns += 1
        case .permissionRequest where event.prompt == .question:
            draft.questions += 1
        case .permissionRequest:
            draft.requests += 1
            let match = Self.clean(event.summary)
            if let index = draft.pendingTests.lastIndex(where: { $0.match == match }) {
                draft.pendingTests[index].asked = true
            }
        case .preToolUse:
            draft.openTools[event.toolName ?? "Tool", default: 0] += 1
            Self.note(event, in: &draft, keepDetails: keepDetails, pending: true)
        case .postToolUse:
            let name = event.toolName ?? "Tool"
            guard draft.openTools[name, default: 0] > 0 else {
                Self.note(event, in: &draft, keepDetails: keepDetails, pending: false)
                return
            }
            draft.openTools[name, default: 0] -= 1
            let key = event.toolUseID ?? Self.testCommand(event).map { Self.clean($0) } ?? ""
            if let index = draft.pendingTests.lastIndex(where: { $0.key == key }) {
                let pending = draft.pendingTests.remove(at: index)
                Self.add(TestRun(command: pending.shown, outcome: Self.outcome(event.source)), to: &draft)
            }
        case .stop, .sessionEnd:
            for pending in draft.pendingTests {
                Self.add(TestRun(command: pending.shown, outcome: Self.unfinished(pending, event.source)), to: &draft)
            }
            draft.pendingTests = []
            draft.openTools = [:]
        default: break
        }
    }

    /// A test that never reported back by the end of the turn. Only Claude Code's hooks make
    /// that a failure, and not when it was waiting on a permission prompt: it may have been
    /// denied in the terminal, which sends no event.
    static func unfinished(_ pending: PendingTest, _ source: AgentSource) -> TestOutcome {
        guard postMeansSuccess(source) else { return .ran }
        return pending.asked ? .unknown : .notPassed
    }

    /// Call whenever the session's figures change (status bar, transcript), so a counter that
    /// started over is caught at its first reading, before it climbs past the old figure.
    public mutating func figuresChanged(_ session: AgentSession) {
        drafts[session.id]?.baseline.watch(session)
    }

    /// The agent quit without a SessionEnd: its open tests never reported, and there's no telling why.
    public mutating func exited(session id: String) {
        guard var draft = drafts[id] else { return }
        for pending in draft.pendingTests { Self.add(TestRun(command: pending.shown, outcome: .unknown), to: &draft) }
        draft.pendingTests = []
        drafts[id] = draft
    }

    /// A denied call never runs, so its test can't count as a failure. `command` is the
    /// request's command.
    public mutating func denied(session id: String, command: String) {
        let match = Self.clean(command)
        guard let index = drafts[id]?.pendingTests.lastIndex(where: { $0.match == match }) else { return }
        drafts[id]?.pendingTests.remove(at: index)
    }

    /// The record for `session` as it stands, or nil when Wisp never saw it start.
    public func record(_ session: AgentSession, at date: Date) -> SessionRecord? {
        guard let draft = drafts[session.id] else { return nil }
        var base = draft.baseline
        base.watch(session)
        let wall = max(0, date.timeIntervalSince(draft.started))
        func count(_ figure: Figure) -> Int { Int(base.delta(figure, figure.read(session) ?? 0).rounded()) }
        return SessionRecord(
            sessionID: session.id, project: session.project, source: session.source, started: draft.started,
            ended: date, duration: session.duration.map { base.delta(.duration, $0) } ?? wall,
            turns: draft.turns, branch: session.branch, model: session.displayModel,
            cost: session.cost.map { base.delta(.cost, $0) }, costIsReal: session.costIsReal,
            tokens: session.usage.map { _ in count(.tokens) }, linesAdded: count(.linesAdded),
            linesRemoved: count(.linesRemoved), toolCount: max(count(.toolCount), draft.tools.values.reduce(0, +)),
            tools: draft.tools, files: draft.files, commands: draft.commands, tests: draft.tests,
            requests: draft.requests, questions: draft.questions,
            endedWaiting: session.state == .waiting || session.state == .needsApproval)
    }

    public mutating func forget(_ id: String) { drafts[id] = nil }

    /// Drops drafts for sessions that are gone (pruned without an end).
    public mutating func keep(only ids: Set<String>) {
        drafts = drafts.filter { ids.contains($0.key) }
    }

    // MARK: Parts

    private static func note(_ event: AgentEvent, in draft: inout Draft, keepDetails: Bool, pending: Bool) {
        let name = event.toolName ?? "Tool"
        draft.tools[name, default: 0] += 1
        if keepDetails, let file = editedFile(event) { addUnique(file, to: &draft.files, limit: fileLimit) }
        if keepDetails, isShell(name), let command = event.toolInput.command.map(clean), !command.isEmpty {
            addUnique(command, to: &draft.commands, limit: commandLimit)
        }
        guard let test = testCommand(event) else { return }
        let shown = keepDetails ? clean(test) : "Tests"
        if pending {
            draft.pendingTests.append(
                PendingTest(key: event.toolUseID ?? clean(test), match: clean(test), shown: shown))
            if draft.pendingTests.count > testLimit { draft.pendingTests.removeFirst() }
        } else {
            add(TestRun(command: shown, outcome: .ran), to: &draft)
        }
    }

    private static func add(_ run: TestRun, to draft: inout Draft) {
        draft.tests.append(run)
        if draft.tests.count > testLimit { draft.tests.removeFirst(draft.tests.count - testLimit) }
    }

    private static func addUnique(_ value: String, to list: inout [String], limit: Int) {
        guard !list.contains(value), list.count < limit else { return }
        list.append(value)
    }

    /// Claude Code runs PostToolUse only after a call succeeds (PostToolUseFailure, which Wisp
    /// doesn't use, after one fails). Other agents' hooks don't promise that, and Copilot CLI
    /// sends both under one name.
    static func postMeansSuccess(_ source: AgentSource) -> Bool { source == .claude }

    private static func outcome(_ source: AgentSource) -> TestOutcome {
        postMeansSuccess(source) ? .passed : .ran
    }

    /// The shell tool names `ToolLabel` knows.
    static func isShell(_ tool: String) -> Bool {
        ["Bash", "run_shell_command", "bash", "Shell"].contains(tool)
    }

    static let editTools: Set<String> = [
        "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch", "replace", "write_file", "edit", "create",
        "Delete", "write",
    ]

    /// Relative to the session's folder when inside it, else the file's name only.
    static func editedFile(_ event: AgentEvent) -> String? {
        guard let tool = event.toolName, editTools.contains(tool),
            let path = event.toolInput.filePath ?? event.toolInput.notebookPath, !path.isEmpty
        else { return nil }
        let folder = event.cwd.hasSuffix("/") ? event.cwd : event.cwd + "/"
        if !event.cwd.isEmpty, path.hasPrefix(folder) { return String(path.dropFirst(folder.count)) }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    static func testCommand(_ event: AgentEvent) -> String? {
        guard let tool = event.toolName, isShell(tool), let command = event.toolInput.command,
            TestCommand.isTest(command)
        else { return nil }
        return command
    }

    /// Masked, first line, capped.
    static func clean(_ command: String) -> String {
        let line =
            ToolLabel.mask(command).trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return line.count <= commandLength ? line : String(line.prefix(commandLength - 1)) + "…"
    }
}

/// Recognises the common test runners in a shell command.
public enum TestCommand {
    private static let pattern =
        #"(^|[\s;&|(])("#
        + [
            #"make\s+(-\S+\s+)*test\w*"#, #"swift\s+test"#, #"xcodebuild\b.*\btest\b"#,
            #"(npm|pnpm|yarn|bun)\s+(run\s+)?test[\w:.-]*"#, #"npx\s+(jest|vitest|playwright\s+test)"#, #"jest"#,
            #"vitest"#, #"pytest"#, #"python3?\s+-m\s+(pytest|unittest)"#, #"cargo\s+(test|nextest)"#,
            #"go\s+test"#, #"rspec"#, #"mix\s+test"#, #"\S*gradlew?\s+(-\S+\s+)*test\w*"#, #"mvn\s+(-\S+\s+)*test"#,
            #"dotnet\s+test"#, #"phpunit"#, #"deno\s+test"#,
        ].joined(separator: "|") + #")(\s|$|;|&|\|)"#

    private static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern)

    public static func isTest(_ command: String) -> Bool {
        guard let regex else { return false }
        let line = command.split(separator: "\n").joined(separator: " ")
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }
}

/// Finished session runs, newest first, kept across launches. Capped by count and age.
public struct SessionHistory: Codable, Equatable, Sendable {
    public private(set) var records: [SessionRecord] = []

    public static let limit = 200
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    /// The file's format; written with it so a later version can tell old files apart.
    public static let version = 1

    public init(records: [SessionRecord] = []) {
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case version, records
    }

    /// One bad record (a field renamed, a value out of range) is skipped instead of losing the rest.
    private struct Lenient: Decodable {
        let record: SessionRecord?
        init(from decoder: Decoder) throws { record = try? SessionRecord(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([Lenient].self, forKey: .records).compactMap(\.record)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(records, forKey: .records)
    }

    /// The saved file, newest first and pruned. Throws only when the file as a whole can't be
    /// read (not JSON, no records list); bad records inside it are skipped.
    public static func decode(_ data: Data, now: Date) throws -> SessionHistory {
        var history = try JSONDecoder().decode(SessionHistory.self, from: data)
        history.records.sort { $0.ended > $1.ended }
        history.prune(now: now)
        return history
    }

    /// Adds or replaces the record with the same id, keeping its summary when the new one has none.
    public mutating func save(_ record: SessionRecord, now: Date) {
        var record = record
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            if record.summary == nil { record.summary = records[index].summary }
            records.remove(at: index)
        }
        records.append(record)
        records.sort { $0.ended > $1.ended }
        prune(now: now)
    }

    public mutating func setSummary(_ summary: String, for id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].summary = summary
    }

    public mutating func remove(_ id: String) {
        records.removeAll { $0.id == id }
    }

    public mutating func clear() { records = [] }

    public mutating func prune(now: Date) {
        records = Array(records.filter { now.timeIntervalSince($0.ended) < Self.maxAge }.prefix(Self.limit))
    }

    public func search(_ query: String, hidden: Bool) -> [SessionRecord] {
        records.filter { $0.matches(query, hidden: hidden) }
    }
}

/// Lets only the newest write of a file through: each write carries the generation of the data
/// it holds, and one no newer than the last admitted is dropped, so a slow write of older data
/// can't land after a newer one.
public struct WriteGate: Sendable {
    public private(set) var latest = 0

    public init() {}

    public mutating func admit(_ generation: Int) -> Bool {
        guard generation > latest else { return false }
        latest = generation
        return true
    }
}

/// Text for the Done notice and push from a session summary.
public enum SessionSummaryText {
    /// Characters the notch's one-line notice keeps.
    public static let noticeLimit = 120

    /// The summary's first sentence, cut to fit the notice.
    public static func firstSentence(_ summary: String) -> String {
        let text =
            summary.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var sentence = text
        if let end = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            sentence = String(text[..<end.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return sentence.count <= noticeLimit ? sentence : String(sentence.prefix(noticeLimit - 1)) + "…"
    }

    /// "wisp: Fixed the login bug." for the notch, or nil while details are hidden (a summary
    /// can name files and commands) or when there's nothing to say.
    public static func notice(project: String, summary: String?, hidden: Bool) -> String? {
        guard !hidden, let summary else { return nil }
        let sentence = firstSentence(summary)
        return sentence.isEmpty ? nil : "\(project): \(sentence)"
    }
}
