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
    let prompt: PermissionPrompt
    /// Kept for a plan or a question, whose answer sends it back.
    let input: JSONValue?
    /// The diff, command or plan the card can expand to show.
    let preview: ApprovalPreview?
    /// The first changed lines and "+N −M", shown in the card itself.
    let inlineDiff: InlineDiff?
    /// What an AskUserQuestion asks, in order; empty for other requests. Parsed once, since
    /// the question card reads it on every redraw.
    let questions: [AgentQuestion]
    /// The session's folder, where "This project" rules are saved.
    let cwd: String
    /// Suggested "Always allow" rules; empty when the card doesn't offer it.
    let rules: [String]
    /// The card menu's rule choices, narrowest first; each saves its rules.
    let ruleChoices: [[String]]
    /// The changed file's name, all private mode shows of an edit besides its counts.
    let fileName: String?
    /// The changed file's path as the request names it; nil for anything but a file change.
    let filePath: String?
    /// Details were hidden when it arrived, so its history record keeps no summary even if
    /// they're shown again before it's answered.
    let arrivedHidden: Bool

    init(
        id: UUID, sessionID: String, project: String, source: AgentSource, tool: String, summary: String,
        prompt: PermissionPrompt = .tool, input: JSONValue? = nil, preview: ApprovalPreview? = nil,
        inlineDiff: InlineDiff? = nil, fileName: String? = nil, filePath: String? = nil, cwd: String = "",
        rules: [String] = [], ruleChoices: [[String]] = [], arrivedHidden: Bool = false
    ) {
        self.arrivedHidden = arrivedHidden
        self.ruleChoices = ruleChoices
        self.fileName = fileName
        self.filePath = filePath
        self.id = id
        self.sessionID = sessionID
        self.project = project
        self.source = source
        self.tool = tool
        self.summary = summary
        self.prompt = prompt
        self.input = input
        self.preview = preview
        self.inlineDiff = inlineDiff
        self.cwd = cwd
        self.rules = rules
        questions = prompt == .question ? AgentQuestion.parse(input) : []
    }

    /// The card's title: a plan is approved, not "used".
    var title: String { prompt == .plan ? "Approve plan" : tool }
    /// The file after the title's verb, relative to the project ("Edit src/auth.ts").
    var titlePath: String? { filePath.map { FileAnchor.relativePath($0, folder: cwd) } }
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
    /// Bundle ID of the terminal or editor the session runs in, for its icon.
    var terminal: String? = nil
}

/// A session that reached the spend cap, waiting for Keep going, Raise or Stop.
struct SpendCapPrompt: Sendable, Equatable {
    let sessionID: String
    let project: String
    let source: AgentSource
    let crossing: SpendCap.Crossing
    /// Wisp estimated the cost from tokens (Codex, or Claude Code without its status line).
    let estimated: Bool
}

/// A session that has waited on the user past the nudge limit.
struct IdleNudgeMoment: Sendable, Equatable {
    let sessionID: String
    let project: String
    let source: AgentSource
    /// The request it waits on, when Wisp is showing one; nil for a prompt in the terminal.
    let request: AgentApproval?
    let minutes: Int
}

/// The pulse and words for a minimised request's pill; `serial` makes a repeat a change.
struct ApprovalNudge: Sendable, Equatable {
    let approval: UUID
    let text: String
    let serial: Int
}

/// A shortcut pressed for the question card on screen.
struct KeyAnswer: Equatable {
    let approval: UUID
    let action: ApprovalKeys.Action
    let serial: Int
}

/// Receives coding agents' hook events and Claude Code status bar snapshots from the
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
    @ObservationIgnored private let focuser = TerminalFocuser()
    /// Agents seen only by their process (`KnownAgents`), shown as Running sessions.
    let monitor = AgentMonitor()
    @ObservationIgnored private var frontID: UUID?
    /// Keeps one key press to one answer (see `ApprovalKeys.Gate`).
    @ObservationIgnored private var keyGate = ApprovalKeys.Gate()
    /// The latest key answer for a question card; `serial` makes a repeat count as a change.
    private(set) var keyAnswer: KeyAnswer?
    var approvals: [AgentApproval] { queue.items.compactMap { pending[$0] } }
    /// Requests on screen and ones held back by the spend cap: what the terminal could still answer.
    private var waitingApprovals: [AgentApproval] { (queue.items + held).compactMap { pending[$0] } }
    /// Requests from sessions at the spend cap, held off screen until the user chooses.
    @ObservationIgnored private var held: [UUID] = []
    /// Dollars a session may spend before Wisp asks; nil is off. Set from Preferences.
    var spendCap: Double? {
        didSet { if spendCap == nil { for prompt in capPrompts { keepGoing(session: prompt.sessionID) } } }
    }
    @ObservationIgnored private var capState = SpendCap()
    /// Sessions at the cap waiting for a choice, oldest first; the front one is on screen.
    @ObservationIgnored private var capPrompts: [SpendCapPrompt] = []
    /// The spend cap card to show, or nil to take it away.
    var onSpendCap: (SpendCapPrompt?) -> Void = { _ in }
    /// Sources whose hooks call this copy's helper.
    private(set) var connected: Set<AgentSource> = []
    /// Agents that sent a hook since Wisp started, so Settings can say Connected rather than Ready.
    private(set) var seenSources: Set<AgentSource> = []
    /// The on-device AI's summary of each session's last finished turn, for its row's title. In
    /// memory only; a session that's gone takes its summary with it.
    private(set) var summaries: [String: String] = [:]
    /// The line in its file where each waiting edit starts, once Wisp has read the file
    /// (`FileAnchor`). The card on screen holds a copy of its request, so it reads this live.
    private(set) var anchors: [UUID: Int] = [:]
    /// Sources whose hooks call another copy's helper (a dev build, a moved app), which
    /// sends events to that copy instead of this one.
    private(set) var connectedElsewhere: Set<AgentSource> = []
    /// Sources connected to this copy by an older version, missing hooks Wisp now uses.
    private(set) var outdated: Set<AgentSource> = []
    /// Connected sources whose approval wait isn't `approvalTimeout` (push was turned on or off
    /// since they were installed). They're in `outdated` too.
    private(set) var waitMismatched: Set<AgentSource> = []
    /// Who owns Claude Code's status bar.
    private(set) var statusLine: StatusLineState = .none
    /// What Claude Code's status bar becomes when hooks are added. Set from Preferences.
    var terminalBarMode: TerminalBarMode = .wisp
    /// Where context turns amber (and alerts) and red. Set from Preferences.
    var contextThresholds = ContextUsage.Thresholds.standard
    /// Whether passing the warn level alerts. Set from Preferences.
    var contextAlert = true
    /// Whether Claude Code's tool hooks are wanted. Set from Preferences.
    var toolActivity = false
    /// Long tool and reminder limits. Set from Preferences.
    var alertRules = AgentAlertRules() {
        didSet { if alertRules != oldValue { checkAlerts() } }
    }
    /// Dollars a day before the budget notices; nil turns them off. Set from Preferences.
    var dailyBudget: Double?
    /// Notices when a usage window passes the alert level and 95%. Set from Preferences.
    var limitAlerts = true
    /// Notices when a usage window is used up, and when one that passed the alert level starts
    /// over. Set from Preferences.
    var limitExhaustedAlerts = true
    var limitResetAlerts = true
    /// The first limit alert level, in percent. Set from Preferences.
    var limitThreshold = LimitWatch.defaultThreshold {
        didSet { limitWatch.threshold = limitThreshold }
    }
    /// The usage windows the status bar reported last; they're the account's, not a session's.
    private(set) var limitReadings: [UsageReading] = []
    @ObservationIgnored private var limitWatch = LimitWatch()
    /// Wakes when a window that passed the alert level is due to reset.
    @ObservationIgnored private var limitResetTask: Task<Void, Never>?
    @ObservationIgnored private var limitResetAt: Date?
    /// Whether card shortcuts use Hyper (true) or ⌃⌥⌘, read from the hotkeys. Set by AppDelegate.
    @ObservationIgnored var keysUseHyper: @MainActor () -> Bool = { false }
    /// The newest tool requests from the approval history, for "Always allow" match counts.
    /// Set by AppServices.
    @ObservationIgnored var recentRequests: @MainActor () -> [ApprovalRecord] = { [] }
    /// Connected agents whose hook file has Wisp's tool hooks.
    private(set) var toolHooks: Set<AgentSource> = []

    /// Connected agents whose tool hooks don't match the tool activity choice, so Settings can
    /// name them.
    func toolHooksMismatched(wanted on: Bool) -> [AgentSource] {
        AgentAdapters.all.map(\.source).filter { source in
            connected.contains(source) && !source.toolHookEvents.isEmpty && toolHooks.contains(source) != on
        }
    }
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
    /// What's in UserDefaults, so only a real change is written.
    @ObservationIgnored private var savedSpend: DailySpend
    @ObservationIgnored private var savedLedger: SpendLedger
    /// Status bar snapshots bring cost several times a second; the write waits for a quiet moment.
    @ObservationIgnored private var spendSaves = SaveThrottle(interval: 5)
    @ObservationIgnored private var spendSaveTask: Task<Void, Never>?

    /// Shows or clears the agent activities.
    var onStatus: (AgentStatus?) -> Void = { _ in }
    var onApproval: (AgentApproval?) -> Void = { _ in }
    /// A request that needs the user arrived (not one allowed by Allow All).
    var onNewRequest: () -> Void = {}
    /// An agent moment that can make a sound, and its session; the receiver decides whether it does.
    var onSound: (AgentSoundEvent, _ session: String?) -> Void = { _, _ in }
    /// A short message for the notch, such as a request allowed by Allow All.
    var onNotice: (String) -> Void = { _ in }
    /// A session's context window passed the alert threshold.
    var onContextAlert: (String) -> Void = { _ in }
    /// A session's context window passed Critical at, with the rounded percentage.
    var onContextCritical: (AgentSession, Int) -> Void = { _, _ in }
    /// A tool ran long or spend reached the daily budget: a symbol and a line for the notch.
    var onAlert: (_ symbol: String, _ text: String) -> Void = { _, _ in }
    /// A session has waited for the user past the reminder limit.
    var onNudge: (IdleNudgeMoment) -> Void = { _ in }
    /// The latest idle nudge for a waiting request, so its minimised pill pulses once and says
    /// how long it has waited.
    private(set) var approvalNudge: ApprovalNudge?
    /// Needs you, Done, a usage limit or the budget, for phone push. Fired whatever the notch
    /// shows; the receiver decides what goes out.
    var onMoment: (AgentMoment) -> Void = { _ in }
    /// A session finished a turn (`ended` false) or ended, with its record so far. The receiver
    /// saves it to the history and sends Done to the phone.
    var onRecord: (_ record: SessionRecord, _ ended: Bool) -> Void = { _, _ in }
    /// A request, plan or question ended: answered in Wisp or the terminal, by a rule or timed out.
    var onApprovalRecord: (ApprovalRecord) -> Void = { _ in }
    /// Builds history records from the events; commands and files are left out while hidden.
    @ObservationIgnored private var recorder = SessionRecorder()
    /// `wisp activity` (or a script) posted, changed or ended a live activity. Returns why it
    /// couldn't be done, which goes back to the sender, or nil.
    var onExternalActivity: (ExternalActivityAction) -> String? = { _ in nil }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var lastListenerRestart = Date.distantPast
    /// `start()` cleared the path for its listener, so `stop()` may remove the file.
    @ObservationIgnored private var ownsSocket = false
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var waiting: [UUID: NWConnection] = [:]
    @ObservationIgnored private var timeouts: [UUID: Task<Void, Never>] = [:]
    /// Per waiting request, a watch on the helper process the agent waits on. It exits once the
    /// agent stops waiting (the prompt was answered in the terminal), and the card goes.
    @ObservationIgnored private var hookWatches: [UUID: any DispatchSourceProcess] = [:]
    /// What each waiting request is matched on when later events show it was answered elsewhere.
    @ObservationIgnored private var settleKeys: [UUID: ApprovalSettle.Request<UUID>] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "agents")
    /// Codex sessions mid-turn: a watch on the rollout file and its read throttle.
    @ObservationIgnored private var rolloutWatches:
        [String: (source: any DispatchSourceFileSystemObject, throttle: ReadThrottle)] = [:]
    private static let rolloutInterval: TimeInterval = 1
    /// Claude Code sessions with a request waiting: a watch on the transcript, where the call's
    /// result shows once the prompt is answered in the terminal. Claude Code leaves the hook
    /// running until its timeout then, so the helper's exit comes far too late.
    @ObservationIgnored private var transcriptWatches: [String: TranscriptWatch] = [:]
    private static let transcriptInterval: TimeInterval = 0.25
    /// How far back the first read starts, to find the waiting call's `tool_use` already written.
    private static let transcriptLookBack: Int64 = 1 << 20
    /// Per session: how far into the transcript Wisp has read, and the totals so far.
    @ObservationIgnored private var transcripts: [String: (offset: UInt64, usage: TranscriptUsage)] = [:]
    @ObservationIgnored private var reading: Set<String> = []
    /// Sessions asked to read again while a read was running.
    @ObservationIgnored private var rereads: Set<String> = []
    /// Latest status bar snapshot per session, applied together at most every `liveInterval`.
    @ObservationIgnored private var pendingSnapshots:
        [String: (snapshot: StatusLineSnapshot, source: AgentSource, terminal: String?)] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// Picks the pill again when a Done or Needs you stops outranking other work, or a
    /// finished tool's label stops lingering.
    @ObservationIgnored private var repickTask: Task<Void, Never>?
    /// Checks for agents that quit without a SessionEnd, while any session knows its process.
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    private let exitInterval: Duration = .seconds(15)
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
        let spend =
            defaults.data(forKey: Self.spendKey).flatMap { try? JSONDecoder().decode(DailySpend.self, from: $0) }
            ?? DailySpend()
        let ledger =
            defaults.data(forKey: Self.ledgerKey).flatMap { try? JSONDecoder().decode(SpendLedger.self, from: $0) }
            ?? SpendLedger()
        self.spend = spend
        self.ledger = ledger
        savedSpend = spend
        savedLedger = ledger
        budgetState =
            defaults.data(forKey: Self.budgetKey).flatMap {
                try? JSONDecoder().decode(SpendBudget.State.self, from: $0)
            }
            ?? SpendBudget.State()
    }

    /// Seconds the PermissionRequest hook should wait: longer while phone push is on. Hooks
    /// installed with another wait read as outdated. Set from Preferences.
    var approvalTimeout = HookInstaller.approvalTimeout {
        didSet { if approvalTimeout != oldValue { refreshInstalled() } }
    }
    /// The wait each connected agent's hooks were actually installed with, which can lag behind
    /// `approvalTimeout` until the user updates them.
    @ObservationIgnored private var installedTimeouts: [AgentSource: Int] = [:]
    @ObservationIgnored private var lastInstalledRead: Date?
    /// Counts hook-file reads, so a background read that a newer one overtook is dropped.
    @ObservationIgnored private var installedReads = 0

    /// Answer before the agent's hook timeout so it can still show its own prompt.
    private func approvalWait(_ source: AgentSource) -> Duration {
        let timeout = installedTimeouts[source] ?? HookInstaller.approvalTimeout
        return .seconds(max(timeout - HookInstaller.handBackMargin, 1))
    }

    /// The approval wait in words for the confirm dialogs ("120 s", "10 minutes").
    private var approvalWaitText: String {
        approvalTimeout % 60 == 0 && approvalTimeout > 120 ? "\(approvalTimeout / 60) minutes" : "\(approvalTimeout) s"
    }

    static var socketURL: URL {
        AppSupport.socketURL(
            home: FileManager.default.homeDirectoryForCurrentUser, bundleID: Bundle.main.bundleIdentifier)
    }

    /// Where each agent keeps its hooks (its adapter's `HookFile`).
    nonisolated static func settingsURL(_ source: AgentSource) -> URL {
        source.adapter.hookFile.url(home: FileManager.default.homeDirectoryForCurrentUser)
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
        ownsSocket = true
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

    /// On quit: closes the socket, removes its file and writes any spend not saved yet.
    func stop() {
        restartTask?.cancel()
        restartTask = nil
        // A late state change must not restart the listener after quit.
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        listening = false
        // Only a socket this hub made; another copy of Wisp may be listening on the same path.
        if ownsSocket { unlink(Self.socketURL.path) }
        ownsSocket = false
        flushSpend()
        limitResetTask?.cancel()
        limitResetTask = nil
        limitResetAt = nil
        for id in rolloutWatches.keys { stopRolloutWatch(id) }
        for id in transcriptWatches.keys { stopTranscriptWatch(id) }
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
                sessions: sessions.list, spend: spend, query: query, now: .now, hidden: hiddenReason,
                limits: currentLimits(now: .now))
            reply(connection, report.encoded().map { String(decoding: $0, as: UTF8.self) })
        case .activity(let action):
            let problem = onExternalActivity(action)
            reply(connection, (problem.map(AgentProtocol.ActivityReply.rejected) ?? .accepted).encoded)
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
        // A jump to this session will need the login shell's PATH; read it before then.
        focuser.warmUp()
        // A new prompt or the end of a turn means a pending request was answered in the
        // terminal. (Notification events can arrive while the request is still open.)
        if [.userPromptSubmit, .stop, .sessionEnd].contains(event.kind) { settleApprovals(for: event.sessionID) }
        // So does the requested call finishing, or an interrupted turn.
        let keys = (queue.items + held).compactMap { settleKeys[$0] }
        for id in ApprovalSettle.settled(keys, by: event) { settle(id) }
        let previous = sessions.session(event.sessionID)
        let before = previous?.state
        recorder.observe(event, at: .now, keepDetails: !detailsHidden, session: previous)
        if event.kind == .sessionEnd, let previous { finishRecord(previous) }
        sessions.apply(event, at: .now)
        if !seenSources.contains(event.source) { seenSources.insert(event.source) }
        reportMoment(session: event.sessionID, before: before, stopped: event.kind == .stop)
        if event.kind == .stop {
            onSound(.finished, event.sessionID)
        } else if sessions.session(event.sessionID)?.state == .waiting, before != .waiting {
            // Waiting on a prompt in the terminal (Needs you), which Wisp can't answer.
            onSound(.needsApproval, event.sessionID)
        }
        // Tool activity comes several times a second; the branch and pruning can wait for the
        // next prompt, stop or status bar snapshot.
        if !event.kind.isToolActivity {
            sessions.prune(now: .now, olderThan: 6 * 3600)
            let live = Set(sessions.list.map(\.id))
            recorder.keep(only: live)
            // A session pruned without ending keeps no file watch or read position behind.
            for id in rolloutWatches.keys where !live.contains(id) { stopRolloutWatch(id) }
            transcripts = transcripts.filter { live.contains($0.key) }
            if summaries.keys.contains(where: { !live.contains($0) }) {
                summaries = summaries.filter { live.contains($0.key) }
            }
            if !event.cwd.isEmpty { sessions.setBranch(Self.branch(cwd: event.cwd), session: event.sessionID) }
        }

        if event.isResume {
            ledger.startRun(session: event.sessionID, at: .now)
            saveSpend(adding: 0)
        }
        if event.kind == .stop { refreshUsage(for: event.sessionID) }
        followRollout(event)
        if event.kind == .sessionEnd {
            transcripts[event.sessionID] = nil
            forgetSpendCap(event.sessionID)
        }
        if event.kind == .userPromptSubmit { capState.newTurn(event.sessionID) }

        let capabilities = event.source.adapter.capabilities
        if event.kind == .permissionRequest, !capabilities.contains(.approve) {
            // A monitor-only agent: the request shows in the session, the terminal answers it.
            reply(connection, nil)
        } else if event.kind == .permissionRequest, event.prompt == .question,
            !capabilities.contains(.answerQuestions) || AgentQuestion.parse(event.rawToolInput).isEmpty
        {
            // Nothing Wisp can show, so the terminal asks (Needs you).
            reply(connection, nil)
        } else if event.kind == .permissionRequest, sessions.shouldAutoApprove(event), !capState.isHeld(event.sessionID)
        {
            reply(connection, event.source.adapter.reply(.allow(.tool, input: nil)))
            onApprovalRecord(
                ApprovalRecord(
                    sessionID: event.sessionID, project: event.project, source: event.source,
                    tool: event.toolName ?? "Tool",
                    summary: ApprovalRecord.summary(event.summary, hidden: detailsHidden),
                    outcome: .rule, date: .now))
            sessions.record(.allowed, "Allowed (Allow All)", session: event.sessionID, at: .now)
            sessions.resolveApproval(session: event.sessionID, at: .now)
            onNotice(AgentPrivacy.allowedNotice(tool: event.toolName, summary: event.summary, hidden: detailsHidden))
        } else if event.kind == .permissionRequest {
            let approval = AgentApproval(
                id: UUID(), sessionID: event.sessionID, project: event.project, source: event.source,
                tool: event.toolName ?? "Tool",
                summary: event.summary, prompt: event.prompt,
                input: event.prompt.keepsInput ? event.rawToolInput : nil,
                preview: ApprovalPreview.make(
                    tool: event.toolName ?? "", input: event.rawToolInput, limit: Self.previewLines),
                inlineDiff: event.prompt == .tool
                    ? InlineDiff.make(tool: event.toolName ?? "", input: event.rawToolInput) : nil,
                fileName: InlineDiff.fileName(tool: event.toolName ?? "", input: event.rawToolInput),
                filePath: event.prompt == .tool
                    ? InlineDiff.filePath(tool: event.toolName ?? "", input: event.rawToolInput) : nil,
                cwd: event.cwd, rules: Self.suggestedRules(event), ruleChoices: Self.ruleChoices(event),
                arrivedHidden: detailsHidden)
            pending[approval.id] = approval
            readAnchor(for: approval, input: event.rawToolInput)
            // Held off screen while the spend cap waits for a choice; the timeout still hands it back.
            let isHeld = capState.isHeld(event.sessionID)
            if isHeld { held.append(approval.id) } else { queue.enqueue(approval.id) }
            waiting[approval.id] = connection
            settleKeys[approval.id] = ApprovalSettle.Request(id: approval.id, event: event)
            if let pid = event.hookPID { watchHook(pid, for: approval.id) }
            watchTranscript(for: event)
            startTimeout(approval.id, source: event.source)
            if !isHeld {
                approvalsChanged()
                onNewRequest()
                onSound(approval.prompt == .question ? .question : .needsApproval, approval.sessionID)
            }
        } else {
            reply(connection, nil)
        }
        publishStatus()
    }

    // MARK: Live status

    private func receive(_ snapshot: StatusLineSnapshot, source: AgentSource, terminal: String?) {
        guard let id = snapshot.sessionID else { return }
        focuser.warmUp()
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
            if !seenSources.contains(item.source) { seenSources.insert(item.source) }
            // New spend while it waited: the request or question was answered in the terminal.
            // Only with tool hooks, which count subagents; a subagent spends while the main agent waits.
            if toolHooks.contains(item.source), sessions.movedOn(item.snapshot) {
                for approval in waitingApprovals where approval.sessionID == id { settle(approval.id) }
            }
            let branch = item.snapshot.branch == nil ? Self.branch(cwd: item.snapshot.cwd) : nil
            let pillChanged = sessions.apply(
                item.snapshot, source: item.source, terminal: item.terminal, branch: branch, at: .now)
            if let session = sessions.session(id) { recorder.figuresChanged(session) }
            if let cost = item.snapshot.cost {
                let increase = ledger.record(
                    total: cost, session: id, transcript: item.snapshot.transcriptPath, at: .now)
                saveSpend(adding: increase, project: sessions.session(id)?.project)
            }
            checkSpendCap(session: id)
            checkContext(session: id)
            checkLimits(UsageLimits.readings(item.snapshot.extras))
            if pillChanged { publishStatus() }
        }
    }

    /// Tracked even while the alert is off, so turning it on doesn't fire for a session that
    /// was already past the level. The sounds have their own switches, so they follow the climb
    /// whatever the alert says.
    private func checkContext(session id: String) {
        if let percent = sessions.contextAlert(session: id, threshold: contextThresholds.warn),
            let project = sessions.session(id)?.project
        {
            onSound(.contextWarning, id)
            if contextAlert { onContextAlert(ContextUsage.notice(percent: percent, project: project)) }
        }
        if let percent = sessions.contextCriticalAlert(session: id, threshold: contextThresholds.critical),
            let session = sessions.session(id)
        {
            onSound(.contextCritical, id)
            if contextAlert { onContextCritical(session, Int(percent.rounded())) }
        }
    }

    /// One agent's latest windows. Tracked even while the alerts are off, so turning them on
    /// stays quiet until the next level.
    private func checkLimits(_ readings: [UsageReading]) {
        guard !readings.isEmpty else { return }
        limitReadings = UsageLimits.merge(limitReadings, with: readings)
        announce(limitWatch.record(readings, at: .now))
        scheduleLimitReset()
    }

    /// The sounds have their own switches, so they play whatever the notice switches say;
    /// quiet hours decide for both downstream.
    private func announce(_ alerts: [LimitAlert]) {
        for alert in alerts {
            onSound(alert.sound, nil)
            guard wantsNotice(alert.kind) else { continue }
            onAlert(alert.symbol, alert.text)
            onMoment(.limit(alert.text))
        }
    }

    private func wantsNotice(_ kind: LimitAlert.Kind) -> Bool {
        switch kind {
        case .level: limitAlerts
        case .exhausted: limitExhaustedAlerts
        case .reset: limitResetAlerts
        }
    }

    /// No reading comes in while no session runs, so the reset is caught from the clock.
    /// Snapshots come several times a second, so the timer is only replaced when the time changes.
    private func scheduleLimitReset() {
        let next = limitWatch.nextReset
        guard next != limitResetAt else { return }
        limitResetTask?.cancel()
        limitResetTask = nil
        limitResetAt = next
        guard let next else { return }
        limitResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 1))
            guard !Task.isCancelled, let self else { return }
            self.limitResetTask = nil
            self.limitResetAt = nil
            self.announce(self.limitWatch.resetsDue(at: .now))
            self.scheduleLimitReset()
        }
    }

    /// The usage windows for `wisp status`, with when each runs out at today's pace. A window
    /// past its reset time is stale and left out.
    func currentLimits(now: Date) -> [AgentReport.Limit] {
        limitReadings.filter { $0.resets.map { $0 > now } ?? true }.map { reading in
            AgentReport.Limit(
                window: reading.window.rawValue, percent: reading.percent, resets: reading.resets,
                full: limitWatch.forecast(reading.window, source: reading.source),
                agent: reading.source.displayName)
        }
    }

    /// Reads `.git/HEAD` directly: a few bytes, so it's fine on the main actor.
    private static func branch(cwd: String) -> String? {
        GitHead.branch(cwd: cwd, read: { try? String(contentsOfFile: $0, encoding: .utf8) })
    }

    /// Adds `increase`, the part of a cost not counted before, to today and to `project`, and
    /// saves it with the ledger once the throttle allows.
    private func saveSpend(adding increase: Double, project: String? = nil) {
        if increase > 0 { spend.add(increase, on: .now, project: project) }
        if spend != savedSpend || ledger != savedLedger {
            spendSaves.markChanged()
            scheduleSpendSave()
        }
        if increase > 0 { checkBudget() }
    }

    private func scheduleSpendSave() {
        guard spendSaveTask == nil, let wait = spendSaves.wait(now: .now) else { return }
        spendSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.spendSaveTask = nil
            self.flushSpend()
        }
    }

    /// Writes spend and the ledger now, whichever changed since the last write.
    private func flushSpend() {
        spendSaveTask?.cancel()
        spendSaveTask = nil
        guard spendSaves.isPending else { return }
        if ledger != savedLedger {
            defaults.set(try? JSONEncoder().encode(ledger), forKey: Self.ledgerKey)
            savedLedger = ledger
        }
        if spend != savedSpend {
            defaults.set(try? JSONEncoder().encode(spend), forKey: Self.spendKey)
            savedSpend = spend
        }
        spendSaves.saved(at: .now)
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
        let text = SpendBudget.text(level: level, budget: dailyBudget)
        onAlert("dollarsign.circle", text)
        onMoment(.budget(text))
    }

    /// A session that just started waiting on the user, or finished a turn.
    private func reportMoment(session id: String, before: AgentSession.State?, stopped: Bool) {
        guard let session = sessions.session(id) else { return }
        if stopped {
            // Done goes out with the record, so the receiver can add its summary.
            if let record = recorder.record(session, at: .now) {
                onRecord(record, false)
            } else {
                onMoment(.done(session: id, project: session.project, source: session.source))
            }
        } else if session.state == .waiting, before != .waiting {
            onMoment(.needsYou(session: id, project: session.project, source: session.source))
        }
    }

    // MARK: Approvals

    /// `allow` nil leaves the decision to Claude Code's own prompt.
    func answer(_ id: UUID, allow: Bool?) {
        guard let taken = take(id) else { return }
        let approval = taken.approval
        logOutcome(approval, allow.map { $0 ? .allowed : .denied } ?? .terminal)
        if let connection = taken.connection {
            reply(
                connection,
                allow.flatMap {
                    approval.source.adapter.reply(.decide(approval.prompt, allow: $0, input: approval.input))
                })
        }
        if let allow {
            sessions.record(
                allow ? .allowed : .denied, allow ? "Allowed" : "Denied", session: approval.sessionID, at: .now)
            if !allow { recorder.denied(session: approval.sessionID, command: approval.summary) }
        }
        // Handed back to the terminal (timed out, or answered there) counts as resolved too,
        // so the session doesn't keep saying it waits on the notch.
        sessions.resolveApproval(session: approval.sessionID, at: .now)
        approvalsChanged()
        publishStatus()
    }

    /// Nobody answered in the notch: the terminal asks instead, so the session waits on the
    /// user there (Needs you) rather than looking like it carried on.
    private func handBack(_ id: UUID) {
        guard let taken = take(id) else { return }
        logOutcome(taken.approval, .timedOut)
        if let connection = taken.connection { reply(connection, nil) }
        let before = sessions.session(taken.approval.sessionID)?.state
        sessions.handedBack(session: taken.approval.sessionID, at: .now)
        reportMoment(session: taken.approval.sessionID, before: before, stopped: false)
        approvalsChanged()
        publishStatus()
    }

    /// Hands a request back to the terminal and brings that terminal forward, since the agent
    /// asks there now.
    func answerInTerminal(_ id: UUID) {
        guard let session = approvals.first(where: { $0.id == id })?.sessionID else { return }
        answer(id, allow: nil)
        focus(session: session)
    }

    /// Denies a request and tells Claude why, in the words typed on the card.
    func deny(_ id: UUID, reason: String) {
        guard let taken = take(id) else { return }
        let approval = taken.approval
        logOutcome(approval, .denied)
        if let connection = taken.connection {
            reply(connection, approval.source.adapter.reply(.deny(approval.prompt, reason: reason)))
        }
        sessions.record(.denied, "Denied", session: approval.sessionID, at: .now)
        recorder.denied(session: approval.sessionID, command: approval.summary)
        sessions.resolveApproval(session: approval.sessionID, at: .now)
        approvalsChanged()
        publishStatus()
    }

    /// Tells the history how a request ended. Only a tool request keeps its summary (the command or
    /// file), never a plan's title or a question, and none while details are hidden or were when
    /// it arrived.
    private func logOutcome(_ approval: AgentApproval, _ outcome: ApprovalOutcome) {
        onApprovalRecord(
            ApprovalRecord(
                sessionID: approval.sessionID, project: approval.project, source: approval.source, tool: approval.tool,
                summary: approval.prompt == .tool
                    ? ApprovalRecord.summary(approval.summary, hidden: detailsHidden || approval.arrivedHidden) : nil,
                outcome: outcome, date: .now))
    }

    /// Hands a session's last record over as it ends and lets its draft go.
    /// `exited` marks a run whose agent quit without ending its session.
    private func finishRecord(_ session: AgentSession, exited: Bool? = nil) {
        if var record = recorder.record(session, at: .now) {
            record.exited = exited
            onRecord(record, true)
        }
        recorder.forget(session.id)
    }

    /// Lines of a diff or new file an approval card shows at most.
    private static let previewLines = 40

    /// Reads an edit's file off the main actor to find the line it starts on, so the card can
    /// number its diff. Only files under the session's folder and up to `FileAnchor.maxBytes`,
    /// never in private mode; the text is matched and dropped, never kept or logged. A read that
    /// fails (folder access denied, file gone) leaves the diff without numbers.
    private func readAnchor(for approval: AgentApproval, input: JSONValue?) {
        guard !detailsHidden, let target = FileAnchor.target(tool: approval.tool, input: input),
            let path = FileAnchor.absolute(target.path, folder: approval.cwd)
        else { return }
        let (id, folder, text) = (approval.id, approval.cwd, target.text)
        Task { [weak self] in
            let line = await Task.detached(priority: .utility) {
                Self.anchorLine(path: path, folder: folder, text: text)
            }.value
            guard let self, let line, self.pending[id] != nil else { return }
            self.anchors[id] = line
        }
    }

    private nonisolated static func anchorLine(path: String, folder: String, text: String) -> Int? {
        // Links are followed first, so one inside the project can't lead the read outside it.
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let base = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        guard FileAnchor.isInside(file.path, folder: base),
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true, let size = values.fileSize, size <= FileAnchor.maxBytes,
            let data = try? Data(contentsOf: file), let contents = String(data: data, encoding: .utf8)
        else { return nil }
        return FileAnchor.line(of: text, in: contents)
    }

    /// Keeps a finished turn's summary for the session's title.
    func setSummary(_ summary: String?, session id: String) {
        guard let summary, !summary.isEmpty, sessions.session(id) != nil else { return }
        summaries[id] = summary
    }

    /// Answers a question from the notch; `answers` maps each question's text to its answer.
    func answerQuestion(_ id: UUID, answers: [String: String]) {
        guard let taken = take(id) else { return }
        let approval = taken.approval
        logOutcome(approval, .answered)
        if let connection = taken.connection {
            reply(
                connection,
                approval.input.flatMap { approval.source.adapter.reply(.answer(input: $0, answers: answers)) })
        }
        sessions.answeredQuestion(session: approval.sessionID, at: .now)
        approvalsChanged()
        publishStatus()
    }

    /// Tells the activity layer which card is on screen, and notes when a new one took the front.
    private func approvalsChanged() {
        let front = approvals.first?.id
        if front != frontID {
            frontID = front
            keyGate.cardChanged(at: .now)
        }
        // Nothing left to answer: forget keys whose key-up may never arrive.
        if front == nil { keyGate.releaseAll() }
        onApproval(approvals.first)
    }

    /// Hands the request back to the terminal if nobody answers in time.
    private func startTimeout(_ id: UUID, source: AgentSource) {
        timeouts.removeValue(forKey: id)?.cancel()
        let wait = approvalWait(source)
        timeouts[id] = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.handBack(id)
        }
    }

    // MARK: Spend cap

    /// Asks once a session's spend crosses the cap, holding its next requests until answered.
    private func checkSpendCap(session id: String) {
        guard let session = sessions.session(id),
            let crossing = capState.check(session: id, cost: session.cost, cap: spendCap)
        else { return }
        capPrompts.append(
            SpendCapPrompt(
                sessionID: id, project: session.project, source: session.source, crossing: crossing,
                estimated: !session.costIsReal))
        onSound(.spendCap, id)
        if capPrompts.count == 1 { onSpendCap(capPrompts.first) }
    }

    /// Keep going: no more asking for this session, and its held requests show.
    func keepGoing(session id: String) {
        capState.keepGoing(id)
        capAnswered(id)
    }

    /// Asks again when the session reaches `limit`.
    func raiseCap(session id: String, to limit: Double) {
        capState.raise(id, to: limit)
        capAnswered(id)
    }

    /// Interrupts the session with Esc in its terminal (Accessibility, as paste needs) and denies
    /// what it held, so it stops at the cap. Asks again after the next prompt.
    func stopAtCap(session id: String) {
        capState.stop(id)
        for approval in waitingApprovals where approval.sessionID == id && held.contains(approval.id) {
            deny(approval.id, reason: "Stopped at the spend cap set in Wisp.")
        }
        capAnswered(id)
        guard AccessibilityPermission.isTrusted else {
            onNotice("Allow Accessibility in Settings to stop it from Wisp")
            return
        }
        guard let session = sessions.session(id) else { return }
        focus(session: id)
        Task { [weak self] in
            // Give the terminal time to come forward before the keystroke lands.
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            guard self.terminalInFront(session) else {
                self.onNotice("Couldn't bring the terminal forward. Press Esc there to stop it.")
                return
            }
            PasteShortcut.press(PasteShortcut.escapeKey)
        }
    }

    /// The card closed without a choice (its ×, Esc): the session keeps going.
    func dismissSpendCap() {
        guard let front = capPrompts.first else { return }
        keepGoing(session: front.sessionID)
    }

    private func capAnswered(_ id: String) {
        capPrompts.removeAll { $0.sessionID == id }
        onSpendCap(capPrompts.first)
        let released = held.filter { pending[$0]?.sessionID == id }
        guard !released.isEmpty else { return }
        held.removeAll { released.contains($0) }
        for request in released {
            queue.enqueue(request)
            // Its wait starts now, so a slow choice on the cap card doesn't hand it straight back.
            if let source = pending[request]?.source { startTimeout(request, source: source) }
        }
        approvalsChanged()
        onNewRequest()
        if let first = released.first.flatMap({ pending[$0] }) {
            onSound(first.prompt == .question ? .question : .needsApproval, id)
        }
        publishStatus()
    }

    private func forgetSpendCap(_ id: String) {
        capState.forget(id)
        guard capPrompts.contains(where: { $0.sessionID == id }) else { return }
        capPrompts.removeAll { $0.sessionID == id }
        onSpendCap(capPrompts.first)
    }

    // MARK: Keyboard answers

    /// Answers the card on screen from a fresh key press (Hyper+Y, N or a digit, or the ⌃⌥⌘
    /// fallback; repeats never get here). False when no card shows or the key means nothing
    /// for it, so the key goes elsewhere.
    func answerKey(_ keyCode: UInt16) -> Bool {
        guard let approval = approvals.first,
            let action = ApprovalKeys.action(keyCode: keyCode, prompt: approval.prompt)
        else { return false }
        // Swallowed but ignored: the key wasn't let go since it last answered, or the card or
        // question only just swapped in.
        guard keyGate.press(keyCode, isRepeat: false, at: .now) else { return true }
        switch action {
        case .allow: answer(approval.id, allow: true)
        case .deny: answer(approval.id, allow: false)
        case .pick, .send:
            // The question card keeps which question is showing and what's picked, so it acts on this.
            keyAnswer = KeyAnswer(approval: approval.id, action: action, serial: (keyAnswer?.serial ?? 0) + 1)
        }
        return true
    }

    /// Whether `keyCode` means something on the card in front, so it's swallowed even while
    /// the card is out of sight (a HUD over it) instead of typing into the front app.
    func keyHasAction(_ keyCode: UInt16) -> Bool {
        guard let approval = approvals.first else { return false }
        return ApprovalKeys.action(keyCode: keyCode, prompt: approval.prompt) != nil
    }

    func releaseKey(_ keyCode: UInt16) {
        keyGate.release(keyCode)
    }

    /// The question card moved on to the next question in the same request.
    func questionStepChanged() {
        keyGate.cardChanged(at: .now)
    }

    /// Takes a request off the queue, with the hook call still waiting for its reply.
    private func take(_ id: UUID) -> (approval: AgentApproval, connection: NWConnection?)? {
        guard let approval = pending[id] else { return nil }
        queue.remove(id)
        held.removeAll { $0 == id }
        pending[id] = nil
        anchors[id] = nil
        timeouts.removeValue(forKey: id)?.cancel()
        // Cancelled before the reply goes, since the helper exits once it has it.
        hookWatches.removeValue(forKey: id)?.cancel()
        settleKeys[id] = nil
        if !pending.values.contains(where: { $0.sessionID == approval.sessionID }) {
            stopTranscriptWatch(approval.sessionID)
        }
        return (approval, waiting.removeValue(forKey: id))
    }

    /// Settles `id` when the helper process `pid` exits before Wisp answers.
    private func watchHook(_ pid: Int32, for id: UUID) {
        let watch = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        watch.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pending[id] != nil else { return }
                self.log.notice("a request's hook exited before Wisp answered; handing it back")
                self.settle(id)
            }
        }
        hookWatches[id] = watch
        watch.resume()
        // Gone before the watch started: nothing will report its exit.
        if kill(pid, 0) != 0, errno == ESRCH {
            Task { @MainActor [weak self] in self?.settle(id) }
        }
    }

    /// A request answered somewhere else (the terminal): its card goes, nothing is sent, and the
    /// session carries on. A question answered there counts as answered.
    private func settle(_ id: UUID) {
        guard let approval = pending[id] else { return }
        if approval.prompt == .question { sessions.answeredQuestion(session: approval.sessionID, at: .now) }
        answer(id, allow: nil)
    }

    /// Allows this request and every later one from the same session, until it ends.
    func allowAll(_ id: UUID) {
        guard let approval = approvals.first(where: { $0.id == id }) else { return }
        sessions.allowAll(session: approval.sessionID)
        answer(id, allow: true)
        // Requests from that session already waiting behind this one are allowed too.
        for queued in approvals where queued.sessionID == approval.sessionID && queued.prompt == .tool {
            answer(queued.id, allow: true)
        }
    }

    private func connectionClosed(_ connection: NWConnection) {
        guard let id = waiting.first(where: { $0.value === connection })?.key else { return }
        waiting[id] = nil
        answer(id, allow: nil)
    }

    private func settleApprovals(for session: String) {
        for approval in waitingApprovals where approval.sessionID == session {
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
        watchExits()
    }

    private func watchExits() {
        guard exitTask == nil, sessions.hasProcesses else { return }
        exitTask = Task { [weak self, exitInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: exitInterval)
                guard let self, !Task.isCancelled else { return }
                self.endExitedSessions()
                if !self.sessions.hasProcesses {
                    self.exitTask = nil
                    return
                }
            }
        }
    }

    /// A session whose agent has quit (closed tab, crash, `kill`) ends as if SessionEnd came.
    private func endExitedSessions() {
        let live = sessions.list
        let ended = sessions.endExited(at: .now) { $0.isRunning(info: AgentProcess.systemInfo) }
        guard !ended.isEmpty else { return }
        for id in ended {
            // Quitting without SessionEnd is a crash or a closed terminal: the Failed sound.
            onSound(.failed, id)
            recorder.exited(session: id)
            if let session = live.first(where: { $0.id == id }) { finishRecord(session, exited: true) }
            settleApprovals(for: id)
            transcripts[id] = nil
            stopRolloutWatch(id)
            forgetSpendCap(id)
        }
        publishStatus()
    }

    /// Sends what's gone over a limit and wakes again for the next one.
    private func checkAlerts() {
        let now = Date.now
        let list = sessions.list
        let due = alerts.due(list, rules: alertRules, now: now)
        if let text = AgentAlert.notice(due, hidden: detailsHidden) { onAlert("hourglass", text) }
        var nudged: [IdleNudgeMoment] = []
        for case .nudge(let id, let project, let approval) in due {
            // An approval's card is already showing; a Needs you goes back in the pill.
            if !approval { sessions.nudge(session: id, at: now) }
            guard let session = sessions.session(id) else { continue }
            let request = approvals.first { $0.sessionID == id }
            nudged.append(
                IdleNudgeMoment(
                    sessionID: id, project: project, source: session.source, request: request,
                    minutes: alertRules.nudgeMinutes))
        }
        scheduleAlertCheck(at: alerts.nextCheck(list, rules: alertRules, now: now))
        guard !nudged.isEmpty else { return }
        for moment in nudged {
            if let request = moment.request { showNudge(on: request, moment) }
            onNudge(moment)
        }
        publishStatus()
    }

    /// Puts "Claude Code has waited 5 min" on the request's minimised pill for a few seconds.
    private func showNudge(on request: AgentApproval, _ moment: IdleNudgeMoment) {
        let nudge = ApprovalNudge(
            approval: request.id, text: IdleNudge.text(agent: moment.source.displayName, minutes: moment.minutes),
            serial: (approvalNudge?.serial ?? 0) + 1)
        approvalNudge = nudge
        Task { [weak self] in
            try? await Task.sleep(for: Self.nudgeShown)
            guard let self, self.approvalNudge == nudge else { return }
            self.approvalNudge = nil
        }
    }

    private static let nudgeShown: Duration = .seconds(6)

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
            others: others, terminal: session.terminal)
    }

    // MARK: Token use

    /// Reads what was added to the session's transcript since last time, off the main actor.
    private func refreshUsage(for id: String) {
        guard let path = sessions.session(id)?.transcriptPath else { return }
        // One read at a time; a request meanwhile (the turn's end after a live read) reads again after.
        guard !reading.contains(id) else {
            rereads.insert(id)
            return
        }
        let previous = transcripts[id] ?? (0, TranscriptUsage())
        reading.insert(id)
        Task { [weak self] in
            let next = await Task.detached { Self.read(path: path, from: previous.offset, into: previous.usage) }.value
            guard let self else { return }
            reading.remove(id)
            defer { if rereads.remove(id) != nil { refreshUsage(for: id) } }
            guard sessions.session(id) != nil else { return }
            transcripts[id] = next
            let cost = next.usage.cost()
            // Claude Code's own figure, once its status bar sends one, is the one that counts.
            if sessions.session(id)?.costIsReal != true, let cost {
                saveSpend(
                    adding: ledger.record(total: cost, for: path, at: .now), project: sessions.session(id)?.project)
            }
            sessions.setUsage(next.usage.total, cost: cost, session: id)
            checkSpendCap(session: id)
            if let session = sessions.session(id) { recorder.figuresChanged(session) }
            sessions.setModelID(next.usage.lastModel, session: id)
            // Codex has no status line; its rollout carries the context and plan limits instead.
            if let percent = next.usage.contextPercent,
                sessions.session(id)?.source.adapter.hookFile.statusLine == false
            {
                if sessions.setContextPercent(percent, session: id) { publishStatus() }
                checkContext(session: id)
            }
            checkLimits(next.usage.limits)
        }
    }

    /// Complete lines only: a line still being written is read next time.
    private nonisolated static func read(path: String, from offset: UInt64, into usage: TranscriptUsage) -> (
        offset: UInt64, usage: TranscriptUsage
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (offset, usage) }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else {
            return (offset, usage)
        }
        var usage = usage
        let used = usage.add(complete: data)
        return (offset + UInt64(used), usage)
    }

    // MARK: Live Codex context

    /// Starts or stops following a Codex session's rollout for this event.
    private func followRollout(_ event: AgentEvent) {
        let id = event.sessionID
        if RolloutWatch.stops(event) {
            stopRolloutWatch(id)
        } else if RolloutWatch.starts(event, running: sessions.session(id)?.state == .running),
            rolloutWatches[id] == nil,
            let path = event.transcriptPath
        {
            startRolloutWatch(id, path: path)
        }
    }

    /// A file system source on the rollout: each write asks the throttle, which reads at most
    /// once a second. No polling; nothing runs while Codex writes nothing.
    private func startRolloutWatch(_ id: String, path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                let events = source.data
                if events.contains(.delete) || events.contains(.rename) {
                    self.stopRolloutWatch(id)
                } else {
                    self.rolloutChanged(id)
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        rolloutWatches[id] = (source, ReadThrottle(interval: Self.rolloutInterval))
        source.resume()
    }

    private func stopRolloutWatch(_ id: String) {
        rolloutWatches.removeValue(forKey: id)?.source.cancel()
    }

    private func rolloutChanged(_ id: String) {
        guard let delay = rolloutWatches[id]?.throttle.request(now: .now) else { return }
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, self.rolloutWatches[id] != nil else { return }
            self.rolloutWatches[id]?.throttle.didRead(now: .now)
            self.refreshUsage(for: id)
        }
    }

    // MARK: Answers in the terminal

    private struct TranscriptWatch {
        let source: any DispatchSourceFileSystemObject
        let path: String
        /// Tells this watch from a later one on the same session, for a read that ends after a restart.
        let token = UUID()
        var offset: UInt64
        var calls = TranscriptCalls()
        var throttle: ReadThrottle
        var reading = false
        /// Claude Code wrote again while a read ran.
        var again = false
        /// The first read only learns which calls are open; a result inside it is older history.
        var primed = false
    }

    /// Follows a Claude Code session's transcript while its main agent has a request waiting.
    /// A file system source, read only when Claude Code writes; nothing runs otherwise.
    private func watchTranscript(for event: AgentEvent) {
        let id = event.sessionID
        guard event.source == .claude, event.agentID == nil, transcriptWatches[id] == nil,
            let path = event.transcriptPath
        else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            close(descriptor)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                let events = source.data
                if events.contains(.delete) || events.contains(.rename) {
                    self.stopTranscriptWatch(id)
                } else {
                    self.transcriptChanged(id)
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        let start = UInt64(max(0, info.st_size - Self.transcriptLookBack))
        transcriptWatches[id] = TranscriptWatch(
            source: source, path: path, offset: start, throttle: ReadThrottle(interval: Self.transcriptInterval))
        source.resume()
        readTranscript(id)
    }

    private func stopTranscriptWatch(_ id: String) {
        transcriptWatches.removeValue(forKey: id)?.source.cancel()
    }

    private func transcriptChanged(_ id: String) {
        guard let delay = transcriptWatches[id]?.throttle.request(now: .now) else { return }
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            self?.transcriptWatches[id]?.throttle.didRead(now: .now)
            self?.readTranscript(id)
        }
    }

    /// Reads what Claude Code added, off the main actor, and settles the requests whose call
    /// finished: it ran (allowed in the terminal) or got an error result (refused there).
    private func readTranscript(_ id: String) {
        guard var watch = transcriptWatches[id] else { return }
        guard !watch.reading else {
            transcriptWatches[id]?.again = true
            return
        }
        watch.reading = true
        transcriptWatches[id] = watch
        let (path, offset, calls, token) = (watch.path, watch.offset, watch.calls, watch.token)
        Task { [weak self] in
            let read = await Task.detached { Self.readCalls(path: path, from: offset, into: calls) }.value
            guard let self, var watch = self.transcriptWatches[id], watch.token == token else { return }
            let primed = watch.primed
            let again = watch.again
            watch.offset = read.offset
            watch.calls = read.calls
            watch.primed = true
            watch.reading = false
            watch.again = false
            self.transcriptWatches[id] = watch
            if primed {
                for call in read.finished {
                    let keys = (self.queue.items + self.held).compactMap { self.settleKeys[$0] }
                    for approval in ApprovalSettle.settled(keys, finished: call, session: id) {
                        self.log.notice("a request was answered in the terminal; its call finished in the transcript")
                        self.settle(approval)
                    }
                }
            }
            if again { self.readTranscript(id) }
        }
    }

    /// Complete lines only: a line still being written is read next time.
    private nonisolated static func readCalls(path: String, from offset: UInt64, into calls: TranscriptCalls) -> (
        offset: UInt64, calls: TranscriptCalls, finished: [TranscriptCalls.Call]
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (offset, calls, []) }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else {
            return (offset, calls, [])
        }
        var calls = calls
        let read = calls.add(complete: data)
        return (offset + UInt64(read.used), calls, read.finished)
    }

    // MARK: Jump to terminal

    /// Brings forward the session's tmux pane or terminal tab when the helper said which,
    /// otherwise the terminal or editor it runs in. Without either, opens its folder in Terminal.
    func focus(session id: String) {
        guard let session = sessions.session(id) else { return }
        focuser.focus(TerminalTarget(context: session.terminalContext, bundleID: session.terminal, cwd: session.cwd))
    }

    /// Brings forward the terminal tab a monitored agent runs in, by its tty, or the app it runs
    /// in. Without either, opens its folder in Terminal.
    func focus(monitored session: MonitoredSession) {
        let context = session.tty.map { TerminalContext(environment: [:], tty: $0) }
        focuser.focus(TerminalTarget(context: context, bundleID: session.terminal, cwd: session.cwd))
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
        focus(session: id)
        Task {
            // Give the terminal time to come forward before the keystroke lands.
            try? await Task.sleep(for: .milliseconds(350))
            // The user's clipboard comes back once the terminal has read the paste.
            PasteShortcut.pasteRestoring(text, after: .milliseconds(1500))
        }
        return true
    }

    /// Brings the session's terminal forward and pastes `/compact` into its prompt, without
    /// pressing Return, so nothing is sent until the user does. Pastes only if the session's
    /// terminal really is in front. The clipboard comes back afterwards. Says why it couldn't in a
    /// notice.
    func compact(session id: String) {
        guard let session = sessions.session(id), CompactCommand.supported(session.source) else { return }
        guard AccessibilityPermission.isTrusted else {
            onNotice("Allow Accessibility in Settings to paste /compact")
            return
        }
        focus(session: id)
        Task { [weak self] in
            // Give the terminal time to come forward before the keystroke lands.
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            guard self.terminalInFront(session) else {
                self.onNotice("Couldn't bring the terminal forward. Type /compact there.")
                return
            }
            PasteShortcut.pasteRestoring(CompactCommand.text, after: .seconds(1))
            self.onNotice("Pasted /compact. Press Return in the terminal.")
        }
    }

    /// Whether the app in front is the one the session runs in (Terminal when Wisp doesn't know,
    /// since the jump then opens its folder there), so keys sent now land in it.
    private func terminalInFront(_ session: AgentSession) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == (session.terminal ?? Self.terminalApp)
    }

    private static let terminalApp = "com.apple.Terminal"

    // MARK: Hooks

    func isConnected(_ source: AgentSource) -> Bool { connected.contains(source) }

    /// Where `source` stands for its row in Settings, from the last read of its hook file.
    func integrationStatus(_ source: AgentSource) -> IntegrationStatus {
        let link: HookLink =
            outdated.contains(source)
            ? .outdated : connected.contains(source) ? .this : connectedElsewhere.contains(source) ? .other : .none
        return IntegrationStatus(link: link, sessionSeen: seenSources.contains(source))
    }

    /// What every agent's hook file says about Wisp, read in one pass.
    private struct InstalledHooks: Sendable {
        var here: Set<AgentSource> = []
        var elsewhere: Set<AgentSource> = []
        var old: Set<AgentSource> = []
        var withTools: Set<AgentSource> = []
        var waits: [AgentSource: Int] = [:]
        /// The status bar's owner, from the last file that carries one.
        var statusLine: StatusLineState?
        let timeout: Int
    }

    /// Reads the hook files now. Wisp's own installs, removals and setting changes use this, so
    /// what they show is never a throttled read behind.
    func refreshInstalled() {
        installedReads += 1
        lastInstalledRead = .now
        apply(Self.readInstalled(helper: Self.helperURL?.path ?? "", timeout: approvalTimeout))
    }

    /// For pages that rebuild on every switch: reads at most every 30 seconds, off the main actor.
    func refreshInstalledIfStale() {
        guard RefreshRule.agentHooks.isDue(lastRefresh: lastInstalledRead, now: .now) else { return }
        installedReads += 1
        lastInstalledRead = .now
        let read = installedReads
        let helper = Self.helperURL?.path ?? ""
        let timeout = approvalTimeout
        Task {
            let hooks = await Task.detached(priority: .userInitiated) {
                Self.readInstalled(helper: helper, timeout: timeout)
            }.value
            // A newer read (an install that just finished) already has the files as they are now.
            guard read == installedReads else { return }
            apply(hooks)
        }
    }

    private nonisolated static func readInstalled(helper: String, timeout: Int) -> InstalledHooks {
        var hooks = InstalledHooks(timeout: timeout)
        for adapter in AgentAdapters.all {
            let source = adapter.source
            let file = adapter.hookFile
            let data = (try? Data(contentsOf: settingsURL(source))) ?? Data()
            hooks.waits[source] = try? HookInstaller.installedApprovalTimeout(in: data, file: file)
            let link = (try? HookInstaller.link(in: data, helper: helper, file: file, timeout: timeout))
            switch link ?? HookLink.none {
            case .this: hooks.here.insert(source)
            case .outdated:
                hooks.here.insert(source)
                hooks.old.insert(source)
            case .other: hooks.elsewhere.insert(source)
            case .none: break
            }
            if file.statusLine { hooks.statusLine = (try? StatusLineChain.state(in: data)) ?? StatusLineState.none }
            if (try? HookInstaller.toolsInstalled(in: data, file: file)) == true { hooks.withTools.insert(source) }
        }
        return hooks
    }

    private func apply(_ hooks: InstalledHooks) {
        if let bar = hooks.statusLine, bar != statusLine { statusLine = bar }
        installedTimeouts = hooks.waits
        // A monitor-only agent has no approval hook, so it has no wait to be out of step with.
        let mismatched = hooks.here.filter {
            $0.adapter.hookFile.waitsForApproval && hooks.waits[$0] != hooks.timeout
        }
        if mismatched != waitMismatched { waitMismatched = mismatched }
        let tools = hooks.withTools.intersection(hooks.here)
        if tools != toolHooks { toolHooks = tools }
        if hooks.here != connected { connected = hooks.here }
        monitor.connected = Set(hooks.here.map(\.rawValue))
        if hooks.elsewhere != connectedElsewhere { connectedElsewhere = hooks.elsewhere }
        if hooks.old != outdated { outdated = hooks.old }
    }

    /// Adds Wisp's hooks after the user confirms; keeps a backup of the original file. True when
    /// the file was written.
    @discardableResult
    func installHooks(_ source: AgentSource) -> Bool {
        guard let helper = Self.helperURL, FileManager.default.isExecutableFile(atPath: helper.path) else {
            alert("Wisp's helper is missing", detail: "Rebuild Wisp, then try again.")
            return false
        }
        let adapter = source.adapter
        let file = adapter.hookFile
        let url = Self.settingsURL(source)
        let path = file.displayPath
        let existing = (try? Data(contentsOf: url)) ?? Data()
        // Droid reads settings.json's hooks only while hooks.json is missing, so creating it
        // starts from those hooks rather than hiding them.
        let seed = Self.seed(for: file, at: url)
        let original = seed ?? existing
        let command = HookInstaller.command(helper: helper.path, file: file, timeout: approvalTimeout)
        let withTools = toolActivity && !file.toolEvents.isEmpty
        guard
            let updated = try? withStatusLine(
                HookInstaller.install(
                    into: original, command: command, file: file, tools: withTools, timeout: approvalTimeout),
                file: file, helper: helper.path)
        else {
            alert("Couldn't read \(path)", detail: "Fix the file's \(file.format.syntax), then try again.")
            return false
        }
        let events = file.events.joined(separator: ", ")
        let tools = withTools ? Self.toolSentence : ""
        let bar = file.statusLine ? barSentence(terminalBarMode, original: original) : ""
        let trust = adapter.setupNote.map { " " + $0 } ?? ""
        let waits = file.waitsForApproval
        let fallBack =
            waits
            ? " Permission prompts wait up to \(approvalWaitText) for the notch, then fall back to the terminal."
            : file.reportsWaiting
                ? " Permission prompts stay in the terminal; the session shows Needs you."
                : " Permission prompts stay in \(source.displayName), and Wisp can't tell when one is waiting."
        let wait = waits ? " Permission prompts wait up to \(approvalWaitText) for Wisp." : ""
        let link =
            (try? HookInstaller.link(in: original, helper: helper.path, file: file, timeout: approvalTimeout))
            ?? HookLink.none
        let rewrite =
            file.format.isTOML
            ? "Wisp's entries go at the end and the rest of the file stays as it is."
            : "Your other settings and hooks stay as they are, though the file is rewritten with sorted keys."
        let copied =
            seed != nil && file.seedPath != nil
            ? " Your hooks in ~/\(file.seedPath ?? "") are copied in, since \(source.displayName) reads them only while \(path) is missing."
            : ""
        let confirmed: Bool
        switch link {
        case .none where file.format.isPlugin:
            confirmed = confirm(
                "Add Wisp's plugin to \(source.displayName)?",
                detail: """
                    Wisp adds a plugin at \(path) that sends \(source.displayName)'s session events to Wisp.\(tools) \
                    Permission prompts show in the notch for up to \(approvalWaitText) while \(source.displayName) \
                    asks too; answer in either place. Restart \(source.displayName) to load it.\(trust)
                    """,
                action: "Add Plugin")
        case .none:
            confirmed = confirm(
                "Add Wisp's hooks to \(source.displayName)?",
                detail: """
                    Wisp adds a command hook for \(events) to \(path).\(tools)\(bar) \(rewrite)\(copied) A backup \
                    is saved next to it with .wisp-backup on the end.\(fallBack)\(trust)
                    """,
                action: "Add Hooks")
        case .outdated, .this:
            confirmed = confirm(
                "Update Wisp's hooks for \(source.displayName)?",
                detail: """
                    Wisp brings its hooks in \(path) up to date for this version.\(tools)\(bar)\(wait) The current \
                    file is saved next to it with .wisp-previous on the end.\(trust)\(Self.restartNote([adapter]))
                    """,
                action: "Update Hooks")
        case .other where file.format.isPlugin:
            confirmed = confirm(
                "Point \(source.displayName)'s plugin at this Wisp?",
                detail: """
                    \(path) calls another copy of Wisp, or isn't Wisp's, so this one doesn't see your sessions. \
                    Wisp replaces it with a plugin that calls this copy.\(trust)\(Self.restartNote([adapter]))
                    """,
                action: "Use This Wisp")
        case .other:
            // Hooks from another copy (a dev build, a moved app) are replaced, not added to.
            confirmed = confirm(
                "Point \(source.displayName)'s hooks at this Wisp?",
                detail: """
                    Wisp's hooks in \(path) call another copy of Wisp, so this one doesn't see your sessions. \
                    They'll call this copy instead.\(bar) \(rewrite)\(trust)
                    """,
                action: "Use This Wisp")
        }
        guard confirmed else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The first backup keeps the user's file from before Wisp; later ones would replace it
            // with a copy that already has Wisp's hooks, so `write` keeps those separately.
            if !existing.isEmpty, link == .none {
                try existing.write(to: url.appendingPathExtension("wisp-backup"), options: .atomic)
            }
        } catch {
            alert("Couldn't write \(path)", detail: error.localizedDescription)
            return false
        }
        return write(updated, to: url)
    }

    /// The hooks of the settings file `file` replaces (`HookFile.seedPath`), while `file` doesn't
    /// exist yet; nil otherwise.
    private nonisolated static func seed(for file: HookFile, at url: URL) -> Data? {
        guard let seedPath = file.seedPath, !FileManager.default.fileExists(atPath: url.path),
            let settings = try? Data(
                contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(seedPath))
        else { return nil }
        return HookInstaller.seed(fromSettings: settings)
    }

    /// A file that holds the agent's status line (Claude Code's settings) also gets the status
    /// bar Preferences ask for.
    private func withStatusLine(_ settings: Data, file: HookFile, helper: String) throws -> Data {
        file.statusLine ? try StatusLineChain.install(terminalBarMode, into: settings, helper: helper) : settings
    }

    func removeHooks(_ source: AgentSource) {
        let url = Self.settingsURL(source)
        if source.adapter.hookFile.format.isPlugin {
            removePlugin(source, at: url)
            return
        }
        let statusLine = source.adapter.hookFile.statusLine
        guard let original = try? Data(contentsOf: url),
            let removed = try? HookInstaller.remove(from: original, file: source.adapter.hookFile),
            let updated = statusLine ? try? StatusLineChain.restore(from: removed) : removed
        else { return }
        let detail =
            statusLine
            ? "Only Wisp's entries are removed, and your own status line, if you had one, comes back."
            : "Only Wisp's entries are removed."
        guard confirm("Remove Wisp's hooks from \(source.displayName)?", detail: detail, action: "Remove") else {
            return
        }
        // A hook file of Wisp's own (Copilot CLI's) goes rather than staying behind empty.
        if (try? HookInstaller.isLeftEmpty(updated, file: source.adapter.hookFile)) == true {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                alert("Couldn't remove \(url.path)", detail: error.localizedDescription)
            }
            refreshInstalled()
            return
        }
        write(updated, to: url)
    }

    /// A plugin is Wisp's own file, so disconnecting deletes it.
    private func removePlugin(_ source: AgentSource, at url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        // Someone else's file of the same name is left alone.
        guard OpenCodePlugin.command(in: data)?.contains(HookInstaller.helperName) == true else {
            alert(
                "\(source.adapter.hookFile.displayPath) isn't Wisp's",
                detail:
                    "Wisp didn't write this file, so it leaves it as it is. Remove it yourself if you don't need it.")
            return
        }
        guard
            confirm(
                "Remove Wisp's plugin from \(source.displayName)?",
                detail:
                    "Wisp deletes \(source.adapter.hookFile.displayPath). Restart \(source.displayName) to unload it.",
                action: "Remove")
        else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            alert("Couldn't remove \(url.path)", detail: error.localizedDescription)
        }
        refreshInstalled()
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
        let path = AgentSource.claude.adapter.hookFile.displayPath
        let original = (try? Data(contentsOf: url)) ?? Data()
        guard let updated = try? StatusLineChain.install(mode, into: original, helper: helper.path) else {
            alert("Couldn't read \(path)", detail: "Fix the file's JSON, then try again.")
            return false
        }
        guard updated != original else {
            terminalBarMode = mode
            return true
        }
        let change =
            mode == .off
            ? " Claude Code's status line goes back to how it was before Wisp." : barSentence(mode, original: original)
        guard
            confirm(
                "Change Claude Code's status line?",
                detail:
                    "Wisp edits \(path).\(change) The current file is saved next to it with .wisp-previous on the end.",
                action: "Change")
        else { return false }
        terminalBarMode = mode
        write(updated, to: url)
        return true
    }

    /// Rewrites every connected agent's hooks for a new approval wait (phone push turned on or
    /// off, or its wait changed), after the user confirms. Cancelling leaves the hooks as they
    /// are; they read as outdated, so Settings offers "Update hooks" later.
    func applyApprovalTimeout() {
        guard let helper = Self.helperURL else { return }
        var changes: [(url: URL, data: Data, adapter: AgentAdapter)] = []
        for adapter in AgentAdapters.all where waitMismatched.contains(adapter.source) {
            let file = adapter.hookFile
            let url = Self.settingsURL(adapter.source)
            let original = (try? Data(contentsOf: url)) ?? Data()
            let command = HookInstaller.command(helper: helper.path, file: file, timeout: approvalTimeout)
            let tools = toolActivity && !file.toolEvents.isEmpty
            guard
                let updated = try? withStatusLine(
                    HookInstaller.install(
                        into: original, command: command, file: file, tools: tools, timeout: approvalTimeout),
                    file: file, helper: helper.path)
            else {
                alert(
                    "Couldn't read \(file.displayPath)", detail: "Fix the file's \(file.format.syntax), then try again."
                )
                return
            }
            if updated != original { changes.append((url, updated, adapter)) }
        }
        guard !changes.isEmpty else { return }
        let paths = ListFormatter.localizedString(byJoining: changes.map { $0.adapter.hookFile.displayPath })
        let names = ListFormatter.localizedString(byJoining: changes.map { $0.adapter.displayName })
        let notes =
            changes.compactMap(\.adapter.setupNote).map { " " + $0 }.joined()
            + Self.restartNote(changes.map(\.adapter))
        let longer = approvalTimeout > HookInstaller.approvalTimeout
        let why =
            longer
            ? "Permission prompts wait up to \(approvalWaitText) so you can answer from your phone."
            : "Permission prompts go back to waiting \(approvalWaitText) for the notch."
        guard
            confirm(
                "Update \(names)'s hooks?",
                detail:
                    "\(why) Wisp edits \(paths); the current file is saved next to it with .wisp-previous on the end.\(notes)",
                action: "Update Hooks")
        else { return }
        for change in changes { write(change.data, to: change.url) }
    }

    /// Agents that load Wisp's plugin only at start pick up a changed file after a restart.
    private static func restartNote(_ adapters: [AgentAdapter]) -> String {
        let names = adapters.filter { $0.hookFile.format.isPlugin }.map(\.displayName)
        guard !names.isEmpty else { return "" }
        return " Restart \(ListFormatter.localizedString(byJoining: names)) to load the change."
    }

    private static let toolSentence =
        " Hooks for tool calls show what the agent is doing in the notch; they never make a tool call wait for Wisp."

    /// Adds or removes the tool hooks of every connected agent that has them, after the user
    /// confirms, like `setTerminalBar`. False when the user cancelled.
    func setToolActivity(_ on: Bool) -> Bool {
        guard let helper = Self.helperURL else {
            toolActivity = on
            return true
        }
        var changes: [(url: URL, data: Data, adapter: AgentAdapter)] = []
        for adapter in AgentAdapters.all
        where connected.contains(adapter.source) && !adapter.hookFile.toolEvents.isEmpty {
            let file = adapter.hookFile
            let url = Self.settingsURL(adapter.source)
            let original = (try? Data(contentsOf: url)) ?? Data()
            let command = HookInstaller.command(helper: helper.path, file: file, timeout: approvalTimeout)
            guard
                let updated = try? HookInstaller.install(
                    into: original, command: command, file: file, tools: on, timeout: approvalTimeout)
            else {
                alert(
                    "Couldn't read \(file.displayPath)", detail: "Fix the file's \(file.format.syntax), then try again."
                )
                return false
            }
            if updated != original { changes.append((url, updated, adapter)) }
        }
        guard !changes.isEmpty else {
            toolActivity = on
            return true
        }
        let paths = ListFormatter.localizedString(byJoining: changes.map { $0.adapter.hookFile.displayPath })
        let names = ListFormatter.localizedString(byJoining: changes.map { $0.adapter.displayName })
        let refresh =
            changes.contains { outdated.contains($0.adapter.source) }
            ? " It also brings Wisp's other hooks up to date." : ""
        // Agents that make the user trust changed hooks (Codex's /hooks) say so up front.
        let notes =
            (on ? changes.compactMap(\.adapter.setupNote).map { " " + $0 }.joined() : "")
            + Self.restartNote(changes.map(\.adapter))
        var events: [String] = []
        for event in changes.flatMap(\.adapter.hookFile.toolEvents) where !events.contains(event) {
            events.append(event)
        }
        let change =
            (on
                ? "Wisp adds hooks for \(ListFormatter.localizedString(byJoining: events)) to \(paths). They hand the call to Wisp and return at once, so tool calls never wait for Wisp."
                : "Wisp removes its tool hooks from \(paths).") + refresh + notes
        guard
            confirm(
                on
                    ? (changes.count == 1 ? "Show what \(names) is doing?" : "Show what agents are doing?")
                    : "Stop showing what agents are doing?",
                detail: change + " The current file is saved next to it with .wisp-previous on the end.",
                action: on ? "Add Hooks" : "Remove Hooks")
        else { return false }
        toolActivity = on
        for change in changes { write(change.data, to: change.url) }
        return true
    }

    private func barSentence(_ mode: TerminalBarMode, original: Data) -> String {
        let mine = ((try? StatusLineChain.state(in: original)) ?? .none).userCommand != nil
        switch mode {
        case .wisp:
            return mine
                ? " Wisp's status line replaces yours under Claude Code's prompt; yours comes back if you choose None."
                : " Wisp's status line is added under Claude Code's prompt."
        case .listen:
            return mine ? " Your status line stays, and Wisp reads the session figures through it." : ""
        case .off: return ""
        }
    }

    /// Writes a settings file Wisp has edited before, keeping the version it replaces.
    @discardableResult
    private func write(_ data: Data, to url: URL) -> Bool {
        defer { refreshInstalled() }
        do {
            try SettingsFileWriter.write(data, to: url)
            return true
        } catch {
            alert("Couldn't write \(url.path)", detail: error.localizedDescription)
            return false
        }
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
