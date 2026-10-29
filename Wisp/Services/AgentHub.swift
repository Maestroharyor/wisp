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
    let tool: String
    let summary: String
}

/// Session status for the compact pill.
struct AgentStatus: Sendable, Equatable {
    let project: String
    let state: AgentSession.State
    let started: Date
}

/// Receives Claude Code hook events from the `wisp-agent` helper over a Unix socket,
/// tracks sessions, and answers permission requests from the notch.
@MainActor
@Observable
final class AgentHub {
    private(set) var sessions = AgentSessions()
    private(set) var approvals: [AgentApproval] = []
    private(set) var hooksInstalled = false
    private(set) var listening = false

    /// Shows or clears the agent activities.
    var onStatus: (AgentStatus?) -> Void = { _ in }
    var onApproval: (AgentApproval?) -> Void = { _ in }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var waiting: [UUID: NWConnection] = [:]
    @ObservationIgnored private var timeouts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.maestro.wisp", category: "agents")

    /// Answer before Claude Code's hook timeout so it can still show its own prompt.
    private let approvalWait: Duration = .seconds(HookInstaller.approvalTimeout - 10)

    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wisp/agents.sock")
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
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
                Task { @MainActor in self?.listening = state == .ready }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            log.error("agent socket failed: \(error.localizedDescription, privacy: .public)")
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

        if event.kind == .permissionRequest {
            let approval = AgentApproval(
                id: UUID(), sessionID: event.sessionID, project: event.project, tool: event.toolName ?? "Tool",
                summary: event.summary)
            approvals.append(approval)
            waiting[approval.id] = connection
            timeouts[approval.id] = Task { [weak self, approvalWait] in
                try? await Task.sleep(for: approvalWait)
                guard !Task.isCancelled else { return }
                self?.answer(approval.id, allow: nil)
            }
            onApproval(approvals.first)
        } else {
            reply(connection, nil)
        }
        publishStatus(for: event.sessionID)
    }

    // MARK: Approvals

    /// `allow` nil leaves the decision to Claude Code's own prompt.
    func answer(_ id: UUID, allow: Bool?) {
        guard let approval = approvals.first(where: { $0.id == id }) else { return }
        approvals.removeAll { $0.id == id }
        timeouts.removeValue(forKey: id)?.cancel()
        if let connection = waiting.removeValue(forKey: id) {
            reply(connection, allow.flatMap(PermissionReply.json(allow:)))
        }
        if allow != nil { sessions.resolveApproval(session: approval.sessionID, at: .now) }
        onApproval(approvals.first)
        publishStatus(for: approval.sessionID)
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
        onStatus(AgentStatus(project: session.project, state: session.state, started: session.turnStarted))
    }

    // MARK: Hooks in ~/.claude/settings.json

    func refreshInstalled() {
        let data = (try? Data(contentsOf: Self.settingsURL)) ?? Data()
        hooksInstalled = (try? HookInstaller.isInstalled(in: data)) ?? false
    }

    /// Adds Wisp's hooks after the user confirms; keeps a backup of the original file.
    func installHooks() {
        guard let helper = Self.helperURL, FileManager.default.isExecutableFile(atPath: helper.path) else {
            alert("Wisp's helper is missing", detail: "Rebuild Wisp, then try again.")
            return
        }
        let url = Self.settingsURL
        let original = (try? Data(contentsOf: url)) ?? Data()
        let command = "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        guard let updated = try? HookInstaller.install(into: original, command: command) else {
            alert("Couldn't read ~/.claude/settings.json", detail: "Fix the file's JSON, then try again.")
            return
        }
        let events = HookInstaller.events.joined(separator: ", ")
        guard
            confirm(
                "Add Wisp's hooks to Claude Code?",
                detail: """
                    Wisp adds a command hook for \(events) to ~/.claude/settings.json. Your other settings and hooks \
                    stay as they are, though the file is rewritten with sorted keys. A backup is saved as \
                    settings.json.wisp-backup. Permission prompts wait up to \(HookInstaller.approvalTimeout) s for \
                    the notch, then fall back to the terminal.
                    """,
                action: "Add Hooks")
        else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !original.isEmpty {
                try original.write(to: url.appendingPathExtension("wisp-backup"), options: .atomic)
            }
            try updated.write(to: url, options: .atomic)
        } catch {
            alert("Couldn't write ~/.claude/settings.json", detail: error.localizedDescription)
        }
        refreshInstalled()
    }

    func removeHooks() {
        let url = Self.settingsURL
        guard let original = try? Data(contentsOf: url), let updated = try? HookInstaller.remove(from: original)
        else { return }
        guard
            confirm(
                "Remove Wisp's hooks from Claude Code?", detail: "Only Wisp's entries are removed.", action: "Remove")
        else { return }
        try? updated.write(to: url, options: .atomic)
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
