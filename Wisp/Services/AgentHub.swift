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
}

/// Receives Claude Code and Codex hook events from the `wisp-agent` helper over a Unix
/// socket, tracks sessions (with token use read from their transcripts), answers
/// permission requests from the notch, and brings a session's terminal forward.
@MainActor
@Observable
final class AgentHub {
    private(set) var sessions = AgentSessions()
    /// Waiting requests in arrival order; the front one is the card on screen.
    private(set) var queue = ApprovalQueue<UUID>()
    private var pending: [UUID: AgentApproval] = [:]
    var approvals: [AgentApproval] { queue.items.compactMap { pending[$0] } }
    /// Agents whose hooks point at Wisp.
    private(set) var connected: Set<AgentSource> = []
    private(set) var listening = false
    /// Estimated spend per day across every session, kept for a month.
    private(set) var spend: DailySpend

    /// Shows or clears the agent activities.
    var onStatus: (AgentStatus?) -> Void = { _ in }
    var onApproval: (AgentApproval?) -> Void = { _ in }
    /// A request that needs the user arrived (not one allowed by Allow All).
    var onNewRequest: () -> Void = {}
    /// A short message for the notch, such as a request allowed by Allow All.
    var onNotice: (String) -> Void = { _ in }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var lastListenerRestart = Date.distantPast
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var waiting: [UUID: NWConnection] = [:]
    @ObservationIgnored private var timeouts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "agents")
    /// Per session: how far into the transcript Wisp has read, and the totals so far.
    @ObservationIgnored private var transcripts: [String: (offset: UInt64, usage: TranscriptUsage)] = [:]
    @ObservationIgnored private var reading: Set<String> = []

    @ObservationIgnored private let defaults: UserDefaults
    private static let spendKey = "agentSpend"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spend =
            defaults.data(forKey: Self.spendKey).flatMap { try? JSONDecoder().decode(DailySpend.self, from: $0) }
            ?? DailySpend()
    }

    /// Answer before Claude Code's hook timeout so it can still show its own prompt.
    private let approvalWait: Duration = .seconds(HookInstaller.approvalTimeout - 10)

    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wisp/agents.sock")
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
        guard let event = try? AgentEvent.decode(data) else {
            reply(connection, nil)
            return
        }
        // A new prompt or the end of a turn means a pending request was answered in the
        // terminal. (Notification events can arrive while the request is still open.)
        if [.userPromptSubmit, .stop, .sessionEnd].contains(event.kind) { settleApprovals(for: event.sessionID) }
        sessions.apply(event, at: .now)
        sessions.prune(now: .now, olderThan: 6 * 3600)

        if event.kind == .stop { refreshUsage(for: event.sessionID) }
        if event.kind == .sessionEnd { transcripts[event.sessionID] = nil }

        if event.kind == .permissionRequest, sessions.shouldAutoApprove(event.sessionID) {
            reply(connection, PermissionReply.json(allow: true))
            let what = event.summary.isEmpty ? (event.toolName ?? "a tool") : event.summary
            sessions.record(.allowed, "Allowed (Allow All)", session: event.sessionID, at: .now)
            sessions.resolveApproval(session: event.sessionID, at: .now)
            onNotice("Allowed \(what)")
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
        publishStatus(for: event.sessionID)
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
        publishStatus(for: approval.sessionID)
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

    private func publishStatus(for sessionID: String) {
        guard let session = sessions.list.first(where: { $0.id == sessionID }) ?? sessions.list.first else {
            onStatus(nil)
            return
        }
        onStatus(
            AgentStatus(
                sessionID: session.id, project: session.project, source: session.source, state: session.state,
                started: session.turnStarted))
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
            let increase = (cost ?? 0) - (sessions.session(id)?.cost ?? 0)
            if increase > 0 {
                spend.add(increase, on: .now)
                defaults.set(try? JSONEncoder().encode(spend), forKey: Self.spendKey)
            }
            sessions.setUsage(next.usage.total, cost: cost, session: id)
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
        var next: Set<AgentSource> = []
        for source in [AgentSource.claude, .codex] {
            let data = (try? Data(contentsOf: Self.settingsURL(source))) ?? Data()
            if (try? HookInstaller.isInstalled(in: data)) == true { next.insert(source) }
        }
        if next != connected { connected = next }
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
        let quoted = "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = source == .claude ? quoted : quoted + " --source codex"
        guard let updated = try? HookInstaller.install(into: original, command: command, source: source) else {
            alert("Couldn't read \(path)", detail: "Fix the file's JSON, then try again.")
            return
        }
        let events = source.hookEvents.joined(separator: ", ")
        let trust = source == .codex ? " Codex asks you to trust new hooks once: run /hooks in Codex." : ""
        guard
            confirm(
                "Add Wisp's hooks to \(source.displayName)?",
                detail: """
                    Wisp adds a command hook for \(events) to \(path). Your other settings and hooks stay as they \
                    are, though the file is rewritten with sorted keys. A backup is saved next to it with \
                    .wisp-backup on the end. Permission prompts wait up to \(HookInstaller.approvalTimeout) s for \
                    the notch, then fall back to the terminal.\(trust)
                    """,
                action: "Add Hooks")
        else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Back up only a file Wisp hasn't touched yet; reinstalling would otherwise replace the
            // user's original with a copy that already has Wisp's hooks.
            let hasWispHooks = (try? HookInstaller.isInstalled(in: original)) ?? false
            if !original.isEmpty, !hasWispHooks {
                try original.write(to: url.appendingPathExtension("wisp-backup"), options: .atomic)
            }
            try updated.write(to: url, options: .atomic)
        } catch {
            alert("Couldn't write \(path)", detail: error.localizedDescription)
        }
        refreshInstalled()
    }

    func removeHooks(_ source: AgentSource) {
        let url = Self.settingsURL(source)
        guard let original = try? Data(contentsOf: url), let updated = try? HookInstaller.remove(from: original)
        else { return }
        guard
            confirm(
                "Remove Wisp's hooks from \(source.displayName)?", detail: "Only Wisp's entries are removed.",
                action: "Remove")
        else { return }
        do {
            try updated.write(to: url, options: .atomic)
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
