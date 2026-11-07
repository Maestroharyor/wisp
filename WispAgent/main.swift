import Foundation
import Network
import WispCore

// Coding agents' hook command: forwards the hook's JSON (stdin) to Wisp over a
// Unix socket and prints Wisp's reply (a permission decision, or nothing). It wraps the
// JSON in Wisp's envelope with the agent (`--source codex`, `--source gemini`, `--source copilot`,
// `--source cursor`, `--source opencode`, otherwise Claude Code) and the terminal app it runs in;
// OpenCode runs it from Wisp's plugin. Any failure exits 0 with no output (for Cursor, which reads
// stdout as JSON, its "carry on" reply), so the agent carries on as if no hook ran. Tool activity
// hooks are sent without waiting for a reply.
// `wisp-agent statusline` is Claude Code's status bar (StatusLineCommand), and `status`,
// `watch`, `spend` and `activity` are the `wisp` command line (CLICommand), also run through a
// `wisp` link.

// The socket belongs to the app this helper ships in, so a hook pointing at Wisp Dev
// talks to Wisp Dev and one pointing at Wisp talks to Wisp.
let appBundleID = Bundle.main.executableURL.map(AppSupport.appBundle(containingHelper:)).flatMap(Bundle.init(url:))?
    .bundleIdentifier
let socketPath = AppSupport.socketURL(
    home: FileManager.default.homeDirectoryForCurrentUser, bundleID: appBundleID
).path
let arguments = CommandLine.arguments
let environment = ProcessInfo.processInfo.environment
let terminal = AgentTerminal.bundleID(
    cfBundleIdentifier: environment["__CFBundleIdentifier"], termProgram: environment["TERM_PROGRAM"])

// The bar prints even when Wisp isn't running, so this comes before the socket check.
if arguments.dropFirst().first == StatusLineChain.subcommand {
    StatusLineCommand.run(
        arguments: Array(arguments.dropFirst(2)), socketPath: socketPath, terminal: terminal, environment: environment)
}
// Commands come before reading stdin, which only hooks send.
if let command = AgentCLI.parse(arguments: arguments) {
    CLICommand.run(command, socketPath: socketPath, environment: environment)
}
let source: AgentSource =
    zip(arguments, arguments.dropFirst()).first { $0.0 == "--source" }.flatMap { AgentSource(rawValue: $0.1) }
    ?? .claude
let hookJSON = FileHandle.standardInput.readDataToEndOfFile()
let silentReply = Data((AgentProtocol.silentReply(forHook: hookJSON, source: source) ?? "").utf8)

/// Prints Wisp's reply, or the agent's "nothing to say" when there's none, and exits.
@Sendable func finish(_ reply: Data) -> Never {
    FileHandle.standardOutput.write(reply.isEmpty ? silentReply : reply)
    exit(0)
}

// A Claude Code hook Cursor ran: Cursor's own hooks report that session, if connected.
if CursorHooks.isImported(hookJSON, source: source) { finish(Data()) }
guard FileManager.default.fileExists(atPath: socketPath) else { finish(Data()) }

// The agent that ran this hook, so Wisp can end its session if it quits without saying so.
let agentProcess = AgentProcess.ownerOfThisProcess()
// The pane or tab it runs in, from a fixed list of variables and the agent's tty (the hook's
// own stdio are pipes). A hook run without a terminal falls back to this process's tty.
let terminalContext = TerminalContext(
    environment: environment,
    tty: agentProcess.flatMap { TerminalContext.controllingTTY(of: $0.pid) }
        ?? TerminalContext.controllingTTY(of: getpid()))
// Tool activity fires on every tool call and needs no answer, so it never waits on Wisp.
if AgentProtocol.kind(forHook: hookJSON, source: source) == .tool {
    if let message = AgentProtocol.envelope(
        kind: .tool, source: source, terminal: terminal, process: agentProcess, context: terminalContext,
        payload: hookJSON)
    {
        SocketSend.send(message, to: socketPath, timeout: 0.05)
    }
    finish(Data())
}
let input =
    AgentProtocol.envelope(
        kind: .hook, source: source, terminal: terminal, process: agentProcess, context: terminalContext,
        payload: hookJSON)
    ?? AgentTerminal.tag(hookJSON, source: source, terminal: terminal)
let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)

@Sendable func receive(_ received: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
        let all = received + (data ?? Data())
        if isComplete || error != nil { finish(all) }
        receive(all)
    }
}

// Before the connection is up, failure means Wisp isn't there. Afterwards the pending
// receive reports the end of the reply, so state changes are ignored: Wisp closes the
// socket right after answering, and exiting here would drop that answer.
// Only touched on the main queue, where the connection runs.
nonisolated(unsafe) var connected = false
connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        connected = true
        connection.send(
            content: input, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
        receive(Data())
    case .failed, .waiting, .cancelled:
        if !connected { finish(Data()) }
    default:
        break
    }
}
connection.start(queue: .main)
// Wisp answers approvals within the hook timeout (`--timeout`, longer while phone push is on);
// never outlive it.
let hookTimeout = HookInstaller.timeout(arguments: arguments) ?? HookInstaller.approvalTimeout
DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(hookTimeout + HookInstaller.helperGrace)) { finish(Data()) }
dispatchMain()
