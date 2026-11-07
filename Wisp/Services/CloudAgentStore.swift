import AppKit
import Foundation
import OSLog
import Observation
import WispCore

/// Cloud agent tasks from Codex (`codex cloud list`), Copilot (`gh agent-task list`) and Cursor
/// (its Cloud Agents API), with each recent pull request's CI from `gh pr checks`. Off until the
/// user turns it on. The CLIs use their own logins; the Cursor key comes from the Keychain.
/// Polls on `CloudPollSchedule`. Titles, output and keys are never logged.
@MainActor
@Observable
final class CloudAgentStore {
    enum Availability: Equatable {
        case unchecked
        case available
        /// The CLI isn't on the login shell's PATH, or there's no Cursor key.
        case missing
    }

    /// Every source's tasks, newest first.
    private(set) var tasks: [CloudTask] = []
    private(set) var availability: [CloudSource: Availability] = [:]
    /// Why a source's last look failed, for Settings.
    private(set) var problems: [CloudSource: String] = [:]
    private(set) var hasCursorKey = false
    /// The task `codex cloud apply` is running for.
    private(set) var applying: String?
    private(set) var refreshing = false

    /// A task finished or failed, or its checks went red.
    @ObservationIgnored var onEvent: (CloudEvent) -> Void = { _ in }
    @ObservationIgnored var onNotice: (String, String) -> Void = { _, _ in }

    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var sources: Set<CloudSource> = []
    @ObservationIgnored private var readChecks = true
    @ObservationIgnored private var tools: [String: String]?
    @ObservationIgnored private var loginPath: String?
    @ObservationIgnored private var schedule = CloudPollSchedule()
    @ObservationIgnored private var changes = CloudChanges()
    @ObservationIgnored private var bySource: [CloudSource: [CloudTask]] = [:]
    @ObservationIgnored private var checks: [String: CloudChecks] = [:]
    @ObservationIgnored private var cursorRuns: [String: (updatedAt: Date, run: CursorRun)] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastRefresh: Date?
    /// Settings changed while a look ran, so another follows it.
    @ObservationIgnored private var refreshAgain = false
    /// Check again was pressed; the next look finds the CLIs afresh.
    @ObservationIgnored private var toolsStale = false
    @ObservationIgnored private var firstSeen = CloudFirstSeen()
    /// Checks were read on the last look, so turning them on can be told apart.
    @ObservationIgnored private var checksWereRead = false
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "cloud")

    /// Opening the widget again within this many seconds doesn't look again.
    private let refreshThrottle: TimeInterval = 30

    init() {
        hasCursorKey = KeychainStore.read(.cursorAPIKey) != nil
    }

    // MARK: Lifecycle

    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
    }

    func stop() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        pollTask?.cancel()
        pollTask = nil
    }

    /// Settings that shape what's asked. Turning a source off forgets it, so turning it back on
    /// doesn't announce what happened meanwhile.
    func apply(enabled: Bool, sources: Set<CloudSource>, checks: Bool) {
        let changed = enabled != self.enabled || sources != self.sources || checks != readChecks
        // Turned on again: start every source afresh, so nothing from before is announced.
        if enabled && !self.enabled { CloudSource.allCases.forEach(forget) }
        self.enabled = enabled
        readChecks = checks
        for source in self.sources.subtracting(enabled ? sources : []) { forget(source) }
        self.sources = sources
        if !checks { self.checks = [:] }
        guard enabled else {
            pollTask?.cancel()
            pollTask = nil
            publish()
            return
        }
        if changed {
            lastRefresh = nil
            refreshNow()
        }
    }

    private func forget(_ source: CloudSource) {
        changes.forget(source)
        firstSeen.forget(source)
        bySource[source] = nil
        problems[source] = nil
        if source == .cursor { cursorRuns = [:] }
    }

    /// The widget opened, Settings changed or the Mac woke: look now and restart the schedule.
    /// A look already under way is never cancelled (that would show a false network problem);
    /// one asked for meanwhile runs right after it.
    func refreshNow() {
        guard enabled else { return }
        schedule.wake(now: .now)
        if refreshing {
            if lastRefresh == nil { refreshAgain = true }
            return
        }
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < refreshThrottle {
            if pollTask == nil { scheduleNext() }
            return
        }
        startRefresh()
    }

    /// Marks the look as started before it runs, so a second call in the same moment waits.
    private func startRefresh() {
        // `pollTask` only ever sleeps; the look itself runs in its own task.
        pollTask?.cancel()
        pollTask = nil
        refreshing = true
        lastRefresh = .now
        Task { [weak self] in await self?.refresh() }
    }

    /// Looks for the CLIs again, after the user installs one.
    func checkTools() {
        // Read by the next look, so one under way keeps the tools it started with.
        toolsStale = true
        lastRefresh = nil
        refreshNow()
    }

    // MARK: Looking

    private func refresh() async {
        defer { finishRefresh() }
        guard enabled else { return }
        if toolsStale {
            toolsStale = false
            tools = nil
            loginPath = nil
        }
        await locateTools()
        for source in CloudSource.allCases where sources.contains(source) {
            guard availability[source] == .available, enabled, sources.contains(source) else { continue }
            await look(source)
        }
        let checksOn = readChecks && tool("gh") != nil
        if checksOn {
            // Checks just turned on, or gh just appeared: pull requests already red stay quiet.
            if !checksWereRead { changes.forgetChecks() }
            await readPullRequestChecks()
        }
        checksWereRead = checksOn
        // Turned off while looking: nothing to announce.
        guard enabled else { return }
        let now = Date.now
        for source in CloudSource.allCases where sources.contains(source) && availability[source] == .available {
            guard let list = bySource[source], problems[source] == nil else { continue }
            for event in changes.update(source: source, tasks: list.map(withChecks), now: now) { onEvent(event) }
        }
        publish()
    }

    private func finishRefresh() {
        refreshing = false
        if refreshAgain, enabled {
            refreshAgain = false
            startRefresh()
        } else {
            refreshAgain = false
            scheduleNext()
        }
    }

    private func scheduleNext() {
        pollTask?.cancel()
        guard enabled, let wait = schedule.next(tasks: tasks, now: .now) else {
            pollTask = nil
            return
        }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.pollTask = nil
            self?.startRefresh()
        }
    }

    private func publish() {
        let all = enabled ? sources.flatMap { bySource[$0] ?? [] }.map(withChecks) : []
        tasks = all.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func withChecks(_ task: CloudTask) -> CloudTask {
        var task = task
        task.checks = checks[task.id]
        return task
    }

    private func look(_ source: CloudSource) async {
        do {
            switch source {
            case .codex: bySource[source] = try CloudParse.codex(Data(try await run("codex", CloudCLI.codexList).utf8))
            case .copilot:
                bySource[source] = try CloudParse.copilot(Data(try await run("gh", CloudCLI.copilotList).utf8))
            case .cursor: bySource[source] = try await lookAtCursor()
            }
            bySource[source] = bySource[source].map { firstSeen.stamp($0, now: .now) }
            problems[source] = nil
        } catch {
            problems[source] = Self.describe(error, source: source)
            log.error("cloud \(source.rawValue, privacy: .public) list failed: \(Self.kind(error), privacy: .public)")
        }
    }

    private func readPullRequestChecks() async {
        let all = sources.flatMap { bySource[$0] ?? [] }
        let wanted = CloudLane.needingChecks(all, now: .now)
        let wantedIDs = Set(wanted.map(\.id))
        checks = checks.filter { wantedIDs.contains($0.key) }
        for task in wanted {
            guard let pullRequest = task.pullRequest else { continue }
            let output: String
            do {
                output = try await run("gh", CloudCLI.checks(pullRequest), timeout: .seconds(15))
            } catch let failure as ProcessRunner.Failure where CloudCLI.checksExitCodes.contains(failure.status) {
                output = failure.output
            } catch {
                continue
            }
            checks[task.id] = CloudParse.checks(Data(output.utf8))
        }
    }

    // MARK: CLIs

    /// Finds `codex` and `gh` on the login shell's PATH once, as the command-line tool check does.
    private func locateTools() async {
        if tools == nil {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let output = try? await ProcessRunner.run(
                shell, ["-ilc", CommandLineTool.printPathCommand], timeout: .seconds(5))
            let path =
                output.flatMap(CommandLineTool.path(fromShellOutput:))
                ?? ProcessRunner.userEnvironment["PATH"] ?? ""
            loginPath = path
            let home = NSHomeDirectory()
            var found: [String: String] = [:]
            for name in ["codex", "gh"] {
                found[name] = CloudCLI.find(
                    name, path: path, home: home, isExecutable: FileManager.default.isExecutableFile(atPath:))
            }
            tools = found
        }
        availability[.codex] = tool("codex") == nil ? .missing : .available
        availability[.copilot] = tool("gh") == nil ? .missing : .available
        availability[.cursor] = hasCursorKey ? .available : .missing
    }

    private func tool(_ name: String) -> String? { tools?[name] }

    /// The CLIs get the login shell's PATH, so a `codex` installed with npm finds `node`.
    private var environment: [String: String] {
        var environment = ProcessRunner.userEnvironment
        if let loginPath, !loginPath.isEmpty { environment["PATH"] = loginPath }
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        return environment
    }

    private struct MissingTool: Error {}

    private func run(
        _ name: String, _ arguments: [String], timeout: Duration = .seconds(30), directory: URL? = nil
    ) async throws -> String {
        guard let path = tool(name) else { throw MissingTool() }
        return try await ProcessRunner.run(
            path, arguments, timeout: timeout, environment: environment, directory: directory)
    }

    // MARK: Cursor

    private struct HTTPFailure: Error {
        let status: Int
    }

    private struct NoKey: Error {}

    private func lookAtCursor() async throws -> [CloudTask] {
        guard let key = KeychainStore.read(.cursorAPIKey), let url = CloudCLI.cursorAgentsURL else { throw NoKey() }
        let agents = try CloudParse.cursorAgents(try await get(url, key: key))
        let fetched = cursorRuns.mapValues(\.updatedAt)
        for id in CloudLane.cursorRunsToFetch(agents, fetched: fetched) {
            guard let agent = agents.first(where: { $0.id == id }), let runID = agent.latestRunID,
                let runURL = CloudCLI.cursorRunURL(agent: id, run: runID),
                let run = try? CloudParse.cursorRun(try await get(runURL, key: key))
            else { continue }
            cursorRuns[id] = (agent.updatedAt, run)
        }
        let ids = Set(agents.map(\.id))
        cursorRuns = cursorRuns.filter { ids.contains($0.key) }
        return agents.map { CloudParse.cursorTask($0, run: cursorRuns[$0.id]?.run) }
    }

    private func get(_ url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(CloudCLI.cursorAuthorization(key: key), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request, delegate: CursorRedirects())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HTTPFailure(status: status) }
        return data
    }

    /// Saves the key in the Keychain, or removes it when empty.
    func setCursorKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard KeychainStore.write(trimmed, for: .cursorAPIKey) else {
            problems[.cursor] = "Couldn't save the key in the Keychain"
            return
        }
        hasCursorKey = !trimmed.isEmpty
        forget(.cursor)
        publish()
        lastRefresh = nil
        refreshNow()
    }

    // MARK: Actions

    func open(_ task: CloudTask) {
        guard let url = task.url ?? task.pullRequest else { return }
        NSWorkspace.shared.open(url)
    }

    func openPullRequest(_ task: CloudTask) {
        guard let url = task.pullRequest else { return }
        NSWorkspace.shared.open(url)
    }

    /// Asks which checkout to apply a finished Codex task's diff to, then runs `codex cloud apply`
    /// there. The folder panel is the confirmation; nothing runs if it's cancelled.
    func applyCodexTask(_ task: CloudTask) {
        guard task.canApply, applying == nil, tool("codex") != nil, let arguments = CloudCLI.codexApply(task.taskID)
        else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Apply"
        panel.message = "Choose the checkout to apply the Codex task's changes to."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        applying = task.id
        Task {
            defer { applying = nil }
            do {
                _ = try await run("codex", arguments, timeout: .seconds(120), directory: folder)
                onNotice("checkmark.circle.fill", "Applied the Codex task")
            } catch {
                log.error("codex apply failed: \(Self.kind(error), privacy: .public)")
                onNotice("exclamationmark.triangle.fill", "Couldn't apply the Codex task")
            }
        }
    }

    // MARK: Problems

    private static func describe(_ error: Error, source: CloudSource) -> String {
        switch error {
        case let failure as HTTPFailure where failure.status == 401 || failure.status == 403:
            return "Cursor refused the key"
        case let failure as HTTPFailure where failure.status == 429:
            return "Cursor asked Wisp to slow down; it will try again later"
        case is HTTPFailure, is URLError:
            return "Couldn't reach Cursor"
        case is ProcessRunner.TimedOut:
            return "\(source.displayName) took too long to answer"
        case is CloudParse.Problem:
            return "\(source.displayName) answered in a way Wisp doesn't understand"
        default:
            switch source {
            case .codex: return "Couldn't list tasks. Run codex login in Terminal."
            case .copilot: return "Couldn't list tasks. Run gh auth status in Terminal."
            case .cursor: return "Couldn't list agents"
            }
        }
    }

    /// The kind of failure for the log, never its text.
    private static func kind(_ error: Error) -> String {
        switch error {
        case let failure as ProcessRunner.Failure: "exit \(failure.status)"
        case let failure as HTTPFailure: "status \(failure.status)"
        case is ProcessRunner.TimedOut: "timed out"
        case is CloudParse.Problem: "unexpected output"
        default: String(describing: type(of: error))
        }
    }
}

/// Follows a redirect from a Cursor request only when it stays on the API host, since every
/// request carries the key.
private final class CursorRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        CloudCLI.allowsCursorRedirect(to: request.url) ? request : nil
    }
}
