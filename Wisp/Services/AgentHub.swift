import AppKit
import Network
import OSLog
import Observation
import WispCore

/// A tool call waiting for Allow or Deny in the notch.
struct AgentApproval: Sendable, Equatable, Identifiable {
    let id: UUID
    let sessionID: String
    let project: String
    let source: AgentSource
    let tool: String
    let summary: String
}

/// Session status for the compact pill.
struct AgentStatus: Sendable, Equatable {
    let sessionID: String
    let project: String
    let source: AgentSource
    let state: AgentSession.State
    let started: Date
    var contextPercent: Double? = nil
    var compacting = false
    /// The tool running now, already in its private form when details are hidden.
    var tool: ToolDescription? = nil
    /// Other live sessions, for the count badge.
    var others = 0
}

/// Receives Claude Code and Codex hook events and Claude Code status bar snapshots from the
/// `wisp-agent` helper over a Unix socket, tracks sessions (with live cost and context from
/// the snapshots, token use from their transcripts), answers permission requests from the
/// notch, and brings a session's terminal forward.
@MainActor
@Observable
final class AgentHub {
    private(set) var sessions = AgentSessions()
    /// Waiting requests in arrival order; the front one is the card on screen.
    private(set) var queue = ApprovalQueue<UUID>()
    private var pending: [UUID: AgentApproval] = [:]
    var approvals: [AgentApproval] { queue.items.compactMap { pending[$0] } }
    /// Sources whose hooks call this copy's helper.
    private(set) var connected: Set<AgentSource> = []
    /// Sources whose hooks call another copy's helper (a dev build, a moved app), which
    /// sends events to that copy instead of this one.
    private(set) var connectedElsewhere: Set<AgentSource> = []
    /// Sources connected to this copy by an older version, missing hooks Wisp now uses.
    private(set) var outdated: Set<AgentSource> = []
    /// Who owns Claude Code's status bar.
    private(set) var statusLine: StatusLineState = .none
    /// What Claude Code's status bar becomes when hooks are added. Set from Preferences.
    var terminalBarMode: TerminalBarMode = .wisp
    /// Context percentage that triggers an alert; nil turns the alert off. Set from Preferences.
    var contextThreshold: Double? = ContextUsage.defaultThreshold
    /// Whether Claude Code's tool hooks are wanted. Set from Preferences.
    var toolActivity = false
    /// Long tool and reminder limits. Set from Preferences.
    var alertRules = AgentAlertRules() {
        didSet { if alertRules != oldValue { checkAlerts() } }
    }
    /// Dollars a day before the budget notices; nil turns them off. Set from Preferences.
    var dailyBudget: Double?
    /// Wisp's tool hooks are in Claude Code's settings.
    private(set) var toolsInstalled = false
    // A change republishes the pill so a tool label hides the moment a call starts.
    /// When agent details are hidden. Set from Preferences.
    var privacyMode: AgentPrivacy.Mode = .default {
        didSet { if privacyMode != oldValue { publishStatus() } }
    }
    /// A call is on (from the microphone). Set by AppServices.
    var onCall = false {
        didSet { if onCall != oldValue { publishStatus() } }
    }
    /// Hide details now, whatever the mode; lasts until Wisp quits.
    var hideNow = false {
        didSet { if hideNow != oldValue { publishStatus() } }
    }
    /// Commands, file paths and session names stay off screen.
    var detailsHidden: Bool { AgentPrivacy.hidden(mode: privacyMode, onCall: onCall, manual: hideNow) }
    /// Why details are hidden, or nil when they're shown.
    var hiddenReason: String? { AgentPrivacy.reason(mode: privacyMode, onCall: onCall, manual: hideNow) }
    /// The setting or a call hides details whatever the eye button says.
    var hiddenByRule: Bool { AgentPrivacy.hidden(mode: privacyMode, onCall: onCall, manual: false) }
    private(set) var listening = false
    /// Estimated spend per day across every session, kept for a month.
    private(set) var spend: DailySpend
    /// Cost already added to `spend` per transcript, so a transcript read again isn't counted twice.
    @ObservationIgnored private var ledger: SpendLedger

    /// Shows or clears the agent activities.
    var onStatus: (AgentStatus?) -> Void = { _ in }
    var onApproval: (AgentApproval?) -> Void = { _ in }
    /// A request that needs the user arrived (not one allowed by Allow All).
    var onNewRequest: () -> Void = {}
    /// A short message for the notch, such as a request allowed by Allow All.
    var onNotice: (String) -> Void = { _ in }
    /// A session's context window passed the alert threshold.
    var onContextAlert: (String) -> Void = { _ in }
    /// A tool ran long or spend reached the daily budget: a symbol and a line for the notch.
    var onAlert: (_ symbol: String, _ text: String) -> Void = { _, _ in }
    /// A session has waited for the user past the reminder limit.
    var onReminder: () -> Void = {}

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var lastListenerRestart = Date.distantPast
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var waiting: [UUID: NWConnection] = [:]
    @ObservationIgnored private var timeouts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "agents")
    /// Per session: how far into the transcript Wisp has read, and the totals so far.
    @ObservationIgnored private var transcripts: [String: (offset: UInt64, usage: TranscriptUsage)] = [:]
    @ObservationIgnored private var reading: Set<String> = []
    /// Latest status bar snapshot per session, applied together at most every `liveInterval`.
    @ObservationIgnored private var pendingSnapshots:
        [String: (snapshot: StatusLineSnapshot, source: AgentSource, terminal: String?)] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// Picks the pill again when a Done or Needs you stops outranking other work, or a
    /// finished tool's label stops lingering.
    @ObservationIgnored private var repickTask: Task<Void, Never>?
    @ObservationIgnored private var alerts = AgentAlerts()
    /// Wakes when the next long tool or wait reaches its limit.
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var alertWake: Date?
    @ObservationIgnored private var budgetState: SpendBudget.State
    @ObservationIgnored private var unsupportedLogged: Set<String> = []
    private let liveInterval: Duration = .milliseconds(250)

    @ObservationIgnored private let defaults: UserDefaults
    private static let spendKey = "agentSpend"
    private static let ledgerKey = "agentSpendLedger"
    private static let budgetKey = "agentBudgetState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spend =
            defaults.data(forKey: Self.spendKey).flatMap { try? JSONDecoder().decode(DailySpend.self, from: $0) }
            ?? DailySpend()
        ledger =
            defaults.data(forKey: Self.ledgerKey).flatMap { try? JSONDecoder().decode(SpendLedger.self, from: $0) }
            ?? SpendLedger()
        budgetState =
            defaults.data(forKey: Self.budgetKey).flatMap {
                try? JSONDecoder().decode(SpendBudget.State.self, from: $0)
            }
            ?? SpendBudget.State()
    }

    /// Answer before Claude Code's hook timeout so it can still show its own prompt.
    private let approvalWait: Duration = .seconds(HookInstaller.approvalTimeout - 10)

    static var socketURL: URL {
        AppSupport.socketURL(
            home: FileManager.default.homeDirectoryForCurrentUser, bundleID: Bundle.main.bundleIdentifier)
    }

    /// Where each agent keeps its hooks: Claude Code in its settings, Codex in hooks.json.
    static func settingsURL(_ source: AgentSource) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch source {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        }
    }

    static var helperURL: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(HookInstaller.helperName)
    }

    // MARK: Listening

    func start() {
        refreshInstalled()
        guard listener == nil else { return }
        let path = Self.socketURL.path
        try? FileManager.default.createDirectory(
            at: Self.socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.listening = state == .ready
                    // Hooks need the socket; bring it back rather than going quiet for good.
                    if case .failed = state { self?.restartListener() }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            log.error("agent socket failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let maximumMessage = 1 << 20

    /// Right away the first time, then after a pause, so a socket that keeps failing
    /// doesn't spin but always comes back.
    private func restartListener() {
        listener?.cancel()
        listener = nil
        restartTask?.cancel()
        let wait = Date.now.timeIntervalSince(lastListenerRestart) > 5 ? 0 : 5
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.lastListenerRestart = .now
            self.start()
        }
    }

    private func accept(_ connection: NWConnection) {
        // A hook that was cancelled (Claude Code timed out, or the prompt was answered in
        // the terminal and the session moved on) closes its socket: drop its card.
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in
                    guard let self, let connection else { return }
                    self.connectionClosed(connection)
                }
            default: break
            }
        }
        connection.start(queue: .main)
        read(connection, Data())
    }

    private func read(_ connection: NWConnection, _ received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                let all = received + (data ?? Data())
                // Hook events are small; anything this big is not one of ours.
                guard all.count <= Self.maximumMessage else {
                    connection.cancel()
                    return
                }
                if isComplete || error != nil {
                    self?.handle(all, from: connection)
                } else {
                    self?.read(connection, all)
                }
            }
        }
    }

    private func handle(_ data: Data, from connection: NWConnection) {
        switch try? AgentProtocol.decode(data) {
        case .hook(let event):
            handle(event, from: connection)
        case .statusline(let snapshot, let source, let terminal):
            // Never answered: the helper has already gone.
            connection.cancel()
            receive(snapshot, source: source, terminal: terminal)
        case .query(let query):
            // `wisp status` follows private mode, the same as the notch.
            let report = AgentReport.make(
                sessions: sessions.list, spend: spend, query: query, now: .now, hidden: hiddenReason)
            reply(connection, report.encoded().map { String(decoding: $0, as: UTF8.self) })
        case .unsupported(let name):
            if unsupportedLogged.insert(name).inserted {
                // The name comes from whoever wrote to the socket, so it stays private.
                log.notice("ignoring an agent message this version doesn't know: \(name, privacy: .private)")
            }
            reply(connection, nil)
        case nil:
            reply(connection, nil)
        }
    }

    private func handle(_ event: AgentEvent, from connection: NWConnection) {
        // A new prompt or the end of a turn means a pending request was answered in the
        // terminal. (Notification events can arrive while the request is still open.)
        if [.userPromptSubmit, .stop, .sessionEnd].contains(event.kind) { settleApprovals(for: event.sessionID) }
        sessions.apply(event, at: .now)
        // Tool activity comes several times a second; the branch and pruning can wait for the
        // next prompt, stop or status bar snapshot.
        if !event.kind.isToolActivity {
            sessions.prune(now: .now, olderThan: 6 * 3600)
            if !event.cwd.isEmpty { sessions.setBranch(Self.branch(cwd: event.cwd), session: event.sessionID) }
        }

        if event.isResume {
            ledger.startRun(session: event.sessionID, at: .now)
            saveSpend(adding: 0)
        }
        if event.kind == .stop { refreshUsage(for: event.sessionID) }
        if event.kind == .sessionEnd { transcripts[event.sessionID] = nil }

        if event.kind == .permissionRequest, sessions.shouldAutoApprove(event.sessionID) {
            reply(connection, PermissionReply.json(allow: true))
            sessions.record(.allowed, "Allowed (Allow All)", session: event.sessionID, at: .now)
            sessions.resolveApproval(session: event.sessionID, at: .now)
            onNotice(AgentPrivacy.allowedNotice(tool: event.toolName, summary: event.summary, hidden: detailsHidden))
        } else if event.kind == .permissionRequest {
            let approval = AgentApproval(
                id: UUID(), sessionID: event.sessionID, project: event.project, source: event.source,
                tool: event.toolName ?? "Tool",
                summary: event.summary)
            pending[approval.id] = approval
            queue.enqueue(approval.id)
            waiting[approval.id] = connection
            timeouts[approval.id] = Task { [weak self, approvalWait] in
                try? await Task.sleep(for: approvalWait)
                guard !Task.isCancelled else { return }
                self?.answer(approval.id, allow: nil)
            }
            onApproval(approvals.first)
            onNewRequest()
        } else {
            reply(connection, nil)
        }
        publishStatus()
    }

    // MARK: Live status

    private func receive(_ snapshot: StatusLineSnapshot, source: AgentSource, terminal: String?) {
        guard let id = snapshot.sessionID else { return }
        pendingSnapshots[id] = (snapshot, source, terminal)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self, liveInterval] in
            try? await Task.sleep(for: liveInterval)
            self?.flushSnapshots()
        }
    }

    private func flushSnapshots() {
        flushTask = nil
        let batch = pendingSnapshots
        pendingSnapshots = [:]
        for (id, item) in batch {
            let branch = item.snapshot.branch == nil ? Self.branch(cwd: item.snapshot.cwd) : nil
            let pillChanged = sessions.apply(
                item.snapshot, source: item.source, terminal: item.terminal, branch: branch, at: .now)
            if let cost = item.snapshot.cost {
                let increase = ledger.record(
                    total: cost, session: id, transcript: item.snapshot.transcriptPath, at: .now)
                saveSpend(adding: increase, project: sessions.session(id)?.project)
            }
            // Tracked even while the alert is off, so turning it on doesn't fire for a session
            // that was already past the level.
            let threshold = contextThreshold ?? ContextUsage.defaultThreshold
            if let percent = sessions.contextAlert(session: id, threshold: threshold), contextThreshold != nil,
                let project = sessions.session(id)?.project
            {
                // Short enough for the side of the pill; the gauge says it's the context.
                onContextAlert("\(Int(percent.rounded()))% · \(project)")
            }
            if pillChanged { publishStatus() }
        }
    }

    /// Reads `.git/HEAD` directly: a few bytes, so it's fine on the main actor.
    private static func branch(cwd: String) -> String? {
        GitHead.branch(cwd: cwd, read: { try? String(contentsOfFile: $0, encoding: .utf8) })
    }

    /// Saves the ledger and adds `increase`, the part of a cost not counted before, to today
    /// and to `project`.
    private func saveSpend(adding increase: Double, project: String? = nil) {
        defaults.set(try? JSONEncoder().encode(ledger), forKey: Self.ledgerKey)
        guard increase > 0 else { return }
        spend.add(increase, on: .now, project: project)
        defaults.set(try? JSONEncoder().encode(spend), forKey: Self.spendKey)
        checkBudget()
    }

    /// Checked only as spend grows, so editing the amount never alerts halfway through typing.
    private func checkBudget() {
        guard let dailyBudget else { return }
        let now = Date.now
        let spent = spend.total(on: now)
        let fired = budgetState.fired(on: now, budget: dailyBudget)
        guard let level = SpendBudget.alert(spent: spent, budget: dailyBudget, fired: fired) else { return }
        budgetState.record(level, on: now, budget: dailyBudget)
        defaults.set(try? JSONEncoder().encode(budgetState), forKey: Self.budgetKey)
        onAlert("dollarsign.circle", SpendBudget.text(level: level, budget: dailyBudget))
    }

    // MARK: Approvals

    /// `allow` nil leaves the decision to Claude Code's own prompt.
    func answer(_ id: UUID, allow: Bool?) {
        guard let approval = approvals.first(where: { $0.id == id }) else { return }
        queue.remove(id)
        pending[id] = nil
        timeouts.removeValue(forKey: id)?.cancel()
        if let connection = waiting.removeValue(forKey: id) {
            reply(connection, allow.flatMap(PermissionReply.json(allow:)))
        }
        if let allow {
            sessions.record(
                allow ? .allowed : .denied, allow ? "Allowed" : "Denied", session: approval.sessionID, at: .now)
            sessions.resolveApproval(session: approval.sessionID, at: .now)
        }
        onApproval(approvals.first)
        publishStatus()
    }

    /// Allows this request and every later one from the same session, until it ends.
    func allowAll(_ id: UUID) {
        guard let approval = approvals.first(where: { $0.id == id }) else { return }
        sessions.allowAll(session: approval.sessionID)
        answer(id, allow: true)
        // Requests from that session already waiting behind this one are allowed too.
        for queued in approvals where queued.sessionID == approval.sessionID { answer(queued.id, allow: true) }
    }

    private func connectionClosed(_ connection: NWConnection) {
        guard let id = waiting.first(where: { $0.value === connection })?.key else { return }
        waiting[id] = nil
        answer(id, allow: nil)
    }

    private func settleApprovals(for session: String) {
        for approval in approvals where approval.sessionID == session {
            answer(approval.id, allow: nil)
        }
    }

    private func reply(_ connection: NWConnection, _ text: String?) {
        connection.send(
            content: Data((text ?? "").utf8), contentContext: .finalMessage, isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Shows the most urgent session (see `AgentUrgency`), with a count of the others.
    private func publishStatus() {
        let all = sessions.list
        let now = Date.now
        let pick = AgentUrgency.pick(all, now: now)
        repickTask?.cancel()
        repickTask = nil
        let wake = [AgentUrgency.momentEnds(all, now: now), pick.primary?.toolLingerEnds(now: now)].compactMap { $0 }
        if let ends = wake.min() {
            repickTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, ends.timeIntervalSince(.now)) + 0.1))
                guard !Task.isCancelled else { return }
                self?.publishStatus()
            }
        }
        onStatus(pick.primary.map { status(for: $0, others: pick.others, now: now) })
        checkAlerts()
    }

    /// Sends what's gone over a limit and wakes again for the next one.
    private func checkAlerts() {
        let now = Date.now
        let list = sessions.list
        let due = alerts.due(list, rules: alertRules, now: now)
        if let text = AgentAlert.notice(due, hidden: detailsHidden) { onAlert("hourglass", text) }
        var reminded = false
        for case .nudge(let id, _, let approval) in due {
            // An approval's card is already showing; a Needs you goes back in the pill.
            if !approval { sessions.nudge(session: id, at: now) }
            reminded = true
        }
        scheduleAlertCheck(at: alerts.nextCheck(list, rules: alertRules, now: now))
        guard reminded else { return }
        onReminder()
        publishStatus()
    }

    /// Tool activity republishes several times a second; the wake-up only moves when the
    /// next limit does.
    private func scheduleAlertCheck(at next: Date?) {
        guard next != alertWake || alertTask == nil else { return }
        alertTask?.cancel()
        alertTask = nil
        alertWake = next
        guard let next else { return }
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSince(.now)) + 0.1))
            guard !Task.isCancelled else { return }
            self?.alertTask = nil
            self?.checkAlerts()
        }
    }

    private func status(for session: AgentSession, others: Int, now: Date) -> AgentStatus {
        AgentStatus(
            sessionID: session.id, project: session.project, source: session.source, state: session.state,
            started: session.turnStarted, contextPercent: session.contextPercent?.rounded(),
            compacting: session.compacting,
            tool: session.state == .running ? session.pillTool(now: now)?.description(hidden: detailsHidden) : nil,
            others: others)
    }

    // MARK: Token use

    /// Reads what was added to the session's transcript since last time, off the main actor.
    private func refreshUsage(for id: String) {
        guard let path = sessions.session(id)?.transcriptPath, !reading.contains(id) else { return }
        let previous = transcripts[id] ?? (0, TranscriptUsage())
        reading.insert(id)
        Task { [weak self] in
            let next = await Task.detached { Self.read(path: path, from: previous.offset, into: previous.usage) }.value
            guard let self else { return }
            reading.remove(id)
            guard sessions.session(id) != nil else { return }
            transcripts[id] = next
            let cost = next.usage.cost()
            // Claude Code's own figure, once its status bar sends one, is the one that counts.
            if sessions.session(id)?.costIsReal != true, let cost {
                saveSpend(
                    adding: ledger.record(total: cost, for: path, at: .now), project: sessions.session(id)?.project)
            }
            sessions.setUsage(next.usage.total, cost: cost, session: id)
            sessions.setModelID(next.usage.lastModel, session: id)
        }
    }

    /// Complete lines only: a line still being written is read next time.
    private nonisolated static func read(path: String, from offset: UInt64, into usage: TranscriptUsage) -> (
        offset: UInt64, usage: TranscriptUsage
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (offset, usage) }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd(),
            let end = data.lastIndex(of: UInt8(ascii: "\n"))
        else { return (offset, usage) }
        var usage = usage
        let complete = data[data.startIndex...end]
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            usage.add(line: String(decoding: line, as: UTF8.self))
        }
        return (offset + UInt64(complete.count), usage)
    }

    // MARK: Jump to terminal

    /// Brings forward the terminal or editor the session runs in. Without one on record,
    /// opens the session's folder in Terminal.
    func focus(session id: String) {
        guard let session = sessions.session(id) else { return }
        if let bundleID = session.terminal {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.activate()
                return
            }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        guard !session.cwd.isEmpty,
            let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: session.cwd)], withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration())
    }

    /// Opens the session's working folder in Finder.
    func openFolder(session id: String) {
        guard let cwd = sessions.session(id)?.cwd, !cwd.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
    }

    /// Shows the session's transcript in Finder; `.jsonl` files have no dependable default app.
    /// False when the file is gone (deleted, or the session was cleaned up).
    func revealTranscript(session id: String) -> Bool {
        guard let path = sessions.session(id)?.transcriptPath, FileManager.default.fileExists(atPath: path) else {
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return true
    }

    func copyID(session id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    /// Pastes a drafted prompt into the session's terminal without sending it, so it can
    /// be checked before pressing Return there. False when Accessibility is missing.
    func sendDraft(_ text: String, to id: String) -> Bool {
        guard AccessibilityPermission.isTrusted else { return false }
        PasteShortcut.stage(text)
        focus(session: id)
        Task {
            // Give the terminal time to come forward before the keystroke lands.
            try? await Task.sleep(for: .milliseconds(350))
            PasteShortcut.send()
        }
        return true
    }

    // MARK: Hooks

    func isConnected(_ source: AgentSource) -> Bool { connected.contains(source) }

    func refreshInstalled() {
        var here: Set<AgentSource> = []
        var elsewhere: Set<AgentSource> = []
        var old: Set<AgentSource> = []
        let helper = Self.helperURL?.path ?? ""
        for source in [AgentSource.claude, .codex] {
            let data = (try? Data(contentsOf: Self.settingsURL(source))) ?? Data()
            switch (try? HookInstaller.link(in: data, helper: helper, source: source)) ?? HookLink.none {
            case .this: here.insert(source)
            case .outdated:
                here.insert(source)
                old.insert(source)
            case .other: elsewhere.insert(source)
            case .none: break
            }
            if source == .claude {
                let bar = (try? StatusLineChain.state(in: data)) ?? .none
                if bar != statusLine { statusLine = bar }
                let tools = (try? HookInstaller.toolsInstalled(in: data)) ?? false
                if tools != toolsInstalled { toolsInstalled = tools }
            }
        }
        if here != connected { connected = here }
        if elsewhere != connectedElsewhere { connectedElsewhere = elsewhere }
        if old != outdated { outdated = old }
    }

    private func displayPath(_ source: AgentSource) -> String {
        source == .claude ? "~/.claude/settings.json" : "~/.codex/hooks.json"
    }

    /// Adds Wisp's hooks after the user confirms; keeps a backup of the original file.
    func installHooks(_ source: AgentSource) {
        guard let helper = Self.helperURL, FileManager.default.isExecutableFile(atPath: helper.path) else {
            alert("Wisp's helper is missing", detail: "Rebuild Wisp, then try again.")
            return
        }
        let url = Self.settingsURL(source)
        let path = displayPath(source)
        let original = (try? Data(contentsOf: url)) ?? Data()
        let command = HookInstaller.command(helper: helper.path, source: source)
        guard
            let updated = try? withStatusLine(
                HookInstaller.install(
                    into: original, command: command, source: source, tools: source == .claude && toolActivity),
                source: source, helper: helper.path)
        else {
            alert("Couldn't read \(path)", detail: "Fix the file's JSON, then try again.")
            return
        }
        let events = source.hookEvents.joined(separator: ", ")
        let tools = source == .claude && toolActivity ? Self.toolSentence : ""
        let bar = source == .claude ? barSentence(terminalBarMode, original: original) : ""
        let trust = source == .codex ? " Codex asks you to trust new hooks once: run /hooks in Codex." : ""
        let link = (try? HookInstaller.link(in: original, helper: helper.path, source: source)) ?? HookLink.none
        let confirmed: Bool
        switch link {
        case .none:
            confirmed = confirm(
                "Add Wisp's hooks to \(source.displayName)?",
                detail: """
                    Wisp adds a command hook for \(events) to \(path).\(tools)\(bar) Your other settings and hooks stay as \
                    they are, though the file is rewritten with sorted keys. A backup is saved next to it with \
                    .wisp-backup on the end. Permission prompts wait up to \(HookInstaller.approvalTimeout) s for \
                    the notch, then fall back to the terminal.\(trust)
                    """,
                action: "Add Hooks")
        case .outdated, .this:
            confirmed = confirm(
                "Update Wisp's hooks for \(source.displayName)?",
                detail: """
                    Wisp brings its hooks in \(path) up to date for this version.\(tools)\(bar) The current file \
                    is saved next to it with .wisp-previous on the end.\(trust)
                    """,
                action: "Update Hooks")
        case .other:
            // Hooks from another copy (a dev build, a moved app) are replaced, not added to.
            confirmed = confirm(
                "Point \(source.displayName)'s hooks at this Wisp?",
                detail: """
                    Wisp's hooks in \(path) call another copy of Wisp, so this one doesn't see your sessions. \
                    They'll call this copy instead.\(bar) Your other settings and hooks stay as they are, though \
                    the file is rewritten with sorted keys.\(trust)
                    """,
                action: "Use This Wisp")
        }
        guard confirmed else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The first backup keeps the user's file from before Wisp; later ones would replace it
            // with a copy that already has Wisp's hooks, so `write` keeps those separately.
            if !original.isEmpty, link == .none {
                try original.write(to: url.appendingPathExtension("wisp-backup"), options: .atomic)
            }
        } catch {
            alert("Couldn't write \(path)", detail: error.localizedDescription)
            return
        }
        write(updated, to: url)
    }

    /// Claude Code's settings also get the status bar Preferences ask for.
    private func withStatusLine(_ settings: Data, source: AgentSource, helper: String) throws -> Data {
        source == .claude ? try StatusLineChain.install(terminalBarMode, into: settings, helper: helper) : settings
    }

    func removeHooks(_ source: AgentSource) {
        let url = Self.settingsURL(source)
        guard let original = try? Data(contentsOf: url),
            let removed = try? HookInstaller.remove(from: original),
            let updated = source == .claude ? try? StatusLineChain.restore(from: removed) : removed
        else { return }
        let detail =
            source == .claude
            ? "Only Wisp's entries are removed, and your own status bar, if you had one, comes back."
            : "Only Wisp's entries are removed."
        guard confirm("Remove Wisp's hooks from \(source.displayName)?", detail: detail, action: "Remove") else {
            return
        }
        write(updated, to: url)
    }

    /// Switches Claude Code's status bar after the user confirms. Only touches the file when
    /// hooks are connected, so choosing a mode before connecting just sets what connecting
    /// will do. False when the user cancelled, so the caller can put the old choice back.
    func setTerminalBar(_ mode: TerminalBarMode) -> Bool {
        guard connected.contains(.claude), let helper = Self.helperURL else {
            terminalBarMode = mode
            return true
        }
        let url = Self.settingsURL(.claude)
        let original = (try? Data(contentsOf: url)) ?? Data()
        guard let updated = try? StatusLineChain.install(mode, into: original, helper: helper.path) else {
            alert("Couldn't read ~/.claude/settings.json", detail: "Fix the file's JSON, then try again.")
            return false
        }
        guard updated != original else {
            terminalBarMode = mode
            return true
        }
        let change =
            mode == .off
            ? " Claude Code's status bar goes back to how it was before Wisp." : barSentence(mode, original: original)
        guard
            confirm(
                "Change Claude Code's status bar?",
                detail:
                    "Wisp edits ~/.claude/settings.json.\(change) The current file is saved next to it with .wisp-previous on the end.",
                action: "Change")
        else { return false }
        terminalBarMode = mode
        write(updated, to: url)
        return true
    }

    private static let toolSentence =
        " Background hooks for tool calls show what Claude is doing in the notch; they never make a tool call wait."

    /// Adds or removes Claude Code's tool hooks after the user confirms, like `setTerminalBar`.
    /// False when the user cancelled.
    func setToolActivity(_ on: Bool) -> Bool {
        guard connected.contains(.claude), let helper = Self.helperURL else {
            toolActivity = on
            return true
        }
        let url = Self.settingsURL(.claude)
        let original = (try? Data(contentsOf: url)) ?? Data()
        let command = HookInstaller.command(helper: helper.path, source: .claude)
        guard let updated = try? HookInstaller.install(into: original, command: command, source: .claude, tools: on)
        else {
            alert("Couldn't read ~/.claude/settings.json", detail: "Fix the file's JSON, then try again.")
            return false
        }
        guard updated != original else {
            toolActivity = on
            return true
        }
        let refresh = outdated.contains(.claude) ? " It also brings Wisp's other hooks up to date." : ""
        let change =
            (on
                ? "Wisp adds three hooks (PreToolUse, PostToolUse and SubagentStop) to ~/.claude/settings.json. They run in the background, so tool calls never wait for them."
                : "Wisp removes its three tool hooks from ~/.claude/settings.json.") + refresh
        guard
            confirm(
                on ? "Show Claude Code's tool activity?" : "Stop showing tool activity?",
                detail: change + " The current file is saved next to it with .wisp-previous on the end.",
                action: on ? "Add Hooks" : "Remove Hooks")
        else { return false }
        toolActivity = on
        write(updated, to: url)
        return true
    }

    private func barSentence(_ mode: TerminalBarMode, original: Data) -> String {
        let mine = ((try? StatusLineChain.state(in: original)) ?? .none).userCommand != nil
        switch mode {
        case .wisp:
            return mine
                ? " Wisp's status bar replaces yours in the terminal; yours comes back if you turn it off."
                : " Wisp's status bar is added to the terminal."
        case .listen:
            return mine ? " Your status bar stays, and Wisp reads the session figures through it." : ""
        case .off: return ""
        }
    }

    /// Writes a settings file Wisp has edited before, keeping the version it replaces.
    private func write(_ data: Data, to url: URL) {
        do {
            if let current = try? Data(contentsOf: url), !current.isEmpty {
                try current.write(to: url.appendingPathExtension("wisp-previous"), options: .atomic)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            alert("Couldn't write \(url.path)", detail: error.localizedDescription)
        }
        refreshInstalled()
    }

    private func confirm(_ title: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func alert(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }
}
