import Foundation

/// Spots a Bash request allowed in the terminal from the agent's processes, well before its
/// result reaches the transcript. Once a call is allowed, Claude Code runs it in a shell it starts
/// itself: `zsh -c '… eval '<command>' …'`, with each `'` in the command written as `'"'"'`. A
/// new process under the agent whose arguments hold the request's command means the call runs.
public enum BashChild {
    /// One row of the process table.
    public struct Entry: Equatable, Sendable {
        public let pid: Int32
        public let parent: Int32
        /// Seconds since 1970, as the kernel reports it.
        public let started: Double

        public init(pid: Int32, parent: Int32, started: Double) {
            self.pid = pid
            self.parent = parent
            self.started = started
        }
    }

    /// How deep under the agent to look: its shell, and a wrapper's child (a sandbox) under that.
    static let maxDepth = 3

    /// The command a Bash request runs; nil when there's none.
    public static func command(of input: JSONValue?) -> String? {
        guard let command = input?["command"]?.stringValue,
            !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return command
    }

    /// Whether a process with `arguments` runs `command`: an argument holds it inside `eval '…'`
    /// (quoted either way a shell quotes `'`), or an argument is the command itself. Looser
    /// matches would let a short command ("ls") match any process that happens to contain it.
    public static func runs(_ command: String, arguments: [String]) -> Bool {
        let quoted = [#"'"'"'"#, #"'\''"#].map { "eval '" + command.replacingOccurrences(of: "'", with: $0) + "'" }
        return arguments.contains { argument in
            argument == command || quoted.contains { argument.contains($0) }
        }
    }

    /// Processes under `agent` (up to `maxDepth` levels) that started at or after `since`, in
    /// table order.
    public static func newDescendants(of agent: Int32, in table: [Entry], since: Double) -> [Int32] {
        var children: [Int32: [Entry]] = [:]
        for entry in table { children[entry.parent, default: []].append(entry) }
        var seen: Set<Int32> = [agent]
        var level = [agent]
        var found: Set<Int32> = []
        for _ in 0..<maxDepth {
            var next: [Int32] = []
            for parent in level {
                for child in children[parent] ?? [] where seen.insert(child.pid).inserted {
                    next.append(child.pid)
                    if child.started >= since { found.insert(child.pid) }
                }
            }
            level = next
        }
        return table.map(\.pid).filter { found.contains($0) }
    }
}
