import AppKit
import OSLog
import WispCore

/// Brings a session's exact pane or tab forward (see `TerminalTarget`): the app comes
/// forward at once, then its tmux pane and its tab in iTerm2, Terminal, Ghostty or WezTerm
/// are selected, and the app is brought forward again over anything that moved. Each step
/// that can't run (no tool, app not running, Automation declined) is skipped, so the worst
/// case is the app coming forward.
@MainActor
final class TerminalFocuser {
    private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "terminal")
    /// The login shell's PATH (nil when the shell didn't answer), read once in the background.
    private var loginPath: Task<String?, Never>?
    /// Apps already sent an AppleScript this launch; the first may wait on the Automation prompt.
    private var scripted: Set<String> = []
    private var working: Task<Void, Never>?

    /// Starts reading the login shell's PATH, which can take seconds, before the first jump.
    func warmUp() {
        guard loginPath == nil else { return }
        loginPath = Task {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let output = try? await ProcessRunner.run(
                shell, ["-ilc", CommandLineTool.printPathCommand], timeout: .seconds(3))
            return output.flatMap(CommandLineTool.path(fromShellOutput:))
        }
    }

    func focus(_ target: TerminalTarget) {
        working?.cancel()
        working = Task { await run(target) }
    }

    private func run(_ target: TerminalTarget) async {
        // Something visible straight away; selecting the pane or tab can take a moment.
        bringForward(target)
        let hadTmux = target.tmux != nil
        var target = target
        var selected = false
        if let pane = target.tmux, let tmux = await tool("tmux") {
            switch await select(pane, tmux: tmux, target: target) {
            case .selected(let clientTTY):
                selected = true
                if let clientTTY { target = target.withClientTTY(clientTTY) }
            case .notAgentsPane:
                target = target.withoutTmux()
            case .failed:
                break
            }
        }
        guard !Task.isCancelled else { return }
        // No app to bring forward and the pane didn't work out: the folder in Terminal after all.
        if hadTmux, !selected, target.bundleID == nil { bringForward(target.withoutTmux()) }
        if let tab = target.tab, await select(tab) { selected = true }
        // Another jump started meanwhile; it brings its own app forward.
        guard !Task.isCancelled, selected, let bundleID = target.bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }

    // MARK: tmux

    private enum TmuxResult {
        /// With the tty of the client showing the pane, which is the host terminal's tab.
        case selected(String?)
        /// The pane's tty isn't the agent's: TMUX came along from a shell started in tmux.
        case notAgentsPane
        case failed
    }

    /// Selects the pane's window and the pane, switching a client to its session when none
    /// shows it.
    private func select(_ pane: TerminalTarget.TmuxPane, tmux: String, target: TerminalTarget) async -> TmuxResult {
        guard
            let info = await runTool(
                tmux, pane.arguments(["display-message", "-p", "-t", pane.pane, TmuxClients.paneFormat])
            ).flatMap(TmuxClients.paneInfo)
        else { return .failed }
        guard target.paneMatches(paneTTY: info.tty) else { return .notAgentsPane }
        let clients = await runTool(tmux, pane.arguments(["list-clients", "-F", TmuxClients.format]))
        let choice = clients.flatMap { TmuxClients.pick(listOutput: $0, session: info.session) }
        if let choice, choice.switchTo {
            _ = await runTool(tmux, pane.arguments(["switch-client", "-c", choice.tty, "-t", pane.pane]))
        }
        _ = await runTool(tmux, pane.arguments(["select-window", "-t", pane.pane]))
        guard await runTool(tmux, pane.arguments(["select-pane", "-t", pane.pane])) != nil else { return .failed }
        return .selected(choice?.tty)
    }

    // MARK: Host tab

    /// True when the tab was found and selected.
    private func select(_ tab: TerminalTarget.Tab) async -> Bool {
        switch tab {
        case .iTermSession(let id):
            return await runScript(TerminalScript.iTerm(sessionID: id), app: TerminalTarget.iTerm)
        case .iTermTTY(let tty): return await runScript(TerminalScript.iTerm(tty: tty), app: TerminalTarget.iTerm)
        case .terminalApp(let tty):
            return await runScript(TerminalScript.terminalApp(tty: tty), app: TerminalTarget.terminalApp)
        case .ghostty(let tty): return await runScript(TerminalScript.ghostty(tty: tty), app: TerminalTarget.ghostty)
        case .wezterm(let pane):
            guard isRunning(TerminalTarget.wezterm), let wezterm = await weztermTool() else { return false }
            return await runTool(wezterm, ["cli", "activate-pane", "--pane-id", pane]) != nil
        }
    }

    /// Only for a running app: `tell application` would launch one that isn't. The first
    /// script to an app gets longer, since macOS may be asking whether Wisp may control it.
    private func runScript(_ script: String, app bundleID: String) async -> Bool {
        guard isRunning(bundleID) else { return false }
        let first = scripted.insert(bundleID).inserted
        return await AppleScriptRunner.run(script, timeout: .seconds(first ? 60 : 3)) == TerminalScript.found
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: App

    /// Brings the app forward (launching it if needed). Without one on record, and with no
    /// tmux pane to go to, opens the session's folder in Terminal.
    private func bringForward(_ target: TerminalTarget) {
        if let bundleID = target.bundleID {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.activate()
                return
            }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        guard target.tmux == nil, let folder = target.folder,
            let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalTarget.terminalApp)
        else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: folder)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Tools

    /// The tool's path, looked up on the login shell's PATH like the `wisp` command check.
    private func tool(_ name: String) async -> String? {
        warmUp()
        let path = await loginPath?.value
        return TerminalTools.candidates(name, path: path, home: NSHomeDirectory())
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// WezTerm's CLI is often only inside the app.
    private func weztermTool() async -> String? {
        if let found = await tool("wezterm") { return found }
        let bundled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalTarget.wezterm)?
            .appendingPathComponent("Contents/MacOS/wezterm").path
        return bundled.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }

    /// The tool's output, or nil when it failed.
    private func runTool(_ path: String, _ arguments: [String]) async -> String? {
        do {
            return try await ProcessRunner.run(
                path, arguments, timeout: .seconds(2), environment: ProcessRunner.userEnvironment)
        } catch {
            let command = arguments.first { !$0.hasPrefix("-") && !$0.hasPrefix("/") } ?? ""
            log.debug(
                "\(URL(fileURLWithPath: path).lastPathComponent, privacy: .public) \(command, privacy: .public) failed")
            return nil
        }
    }
}
