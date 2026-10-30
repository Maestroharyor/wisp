import Foundation
import Network
import WispCore

// Claude Code and Codex hook command: forwards the hook's JSON (stdin) to Wisp over a
// Unix socket and prints Wisp's reply (a permission decision, or nothing). It tags the
// JSON with the agent (`--source codex`, otherwise Claude Code) and the terminal app it
// runs in. Any failure exits 0 with no output, so the agent carries on as if no hook ran.

let socketPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Wisp/agents.sock").path
guard FileManager.default.fileExists(atPath: socketPath) else { exit(0) }

let arguments = CommandLine.arguments
let source: AgentSource =
    zip(arguments, arguments.dropFirst()).first { $0.0 == "--source" }.flatMap { AgentSource(rawValue: $0.1) }
    ?? .claude
let environment = ProcessInfo.processInfo.environment
let terminal = AgentTerminal.bundleID(
    cfBundleIdentifier: environment["__CFBundleIdentifier"], termProgram: environment["TERM_PROGRAM"])
let input = AgentTerminal.tag(FileHandle.standardInput.readDataToEndOfFile(), source: source, terminal: terminal)
let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)

@Sendable func finish(_ reply: Data) -> Never {
    FileHandle.standardOutput.write(reply)
    exit(0)
}

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
        if !connected { exit(0) }
    default:
        break
    }
}
connection.start(queue: .main)
// Wisp answers approvals within the hook timeout; never outlive it.
DispatchQueue.main.asyncAfter(deadline: .now() + 125) { exit(0) }
dispatchMain()
