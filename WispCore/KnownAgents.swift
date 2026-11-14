import Foundation

/// A coding agent Wisp can spot by its process alone: the ones without hooks Wisp can use, and
/// the hook agents before their hooks are installed.
public struct KnownAgent: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// SF Symbol for its mark.
    public let symbol: String
    /// Executable names, as run directly or as the script a launcher runs.
    let binaries: [String]
    /// npm packages, matched as `/node_modules/<package>/` in a launcher's script path.
    let packages: [String]
    /// Python modules, for `python -m <module>`.
    let modules: [String]
    /// For a name other tools share: the subcommands one of its sessions starts with. Run by
    /// name, it counts only with no arguments or with one of these as its first word.
    let subcommands: Set<String>?
    /// The hook adapter's id, for agents Wisp can also connect with hooks.
    public let adapterID: String?

    init(
        id: String, name: String, symbol: String, binaries: [String], packages: [String] = [], modules: [String] = [],
        subcommands: Set<String>? = nil, adapterID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.binaries = binaries
        self.packages = packages
        self.modules = modules
        self.subcommands = subcommands
        self.adapterID = adapterID
    }

    /// Whether `arguments` (after the executable) start a session of this agent.
    func accepts(_ arguments: [String]) -> Bool {
        guard let subcommands, let first = arguments.first(where: { !$0.hasPrefix("-") }) else { return true }
        return subcommands.contains(first)
    }
}

/// Agents Wisp watches by process (Settings › Agents › Integrations shows them as Monitor), and
/// how to recognise them from a process's name and arguments. Many run under `node`, `bun` or
/// Python, so the script a launcher runs counts as well as the executable.
public enum KnownAgents {
    public static let all: [KnownAgent] = [
        KnownAgent(id: "aider", name: "Aider", symbol: "a.circle", binaries: ["aider"], modules: ["aider"]),
        // Also the name of a database migration tool (`goose postgres … up`).
        KnownAgent(
            id: "goose", name: "Goose", symbol: "bird", binaries: ["goose"],
            subcommands: ["session", "s", "run", "web", "term", "acp", "project", "p", "projects", "ps", "recipe"]),
        KnownAgent(id: "amp", name: "Amp", symbol: "bolt", binaries: ["amp"], packages: ["@sourcegraph/amp"]),
        KnownAgent(id: "trae", name: "Trae", symbol: "t.circle", binaries: ["traecli", "trae-cli"]),
        KnownAgent(id: "antigravity", name: "Antigravity", symbol: "arrow.up.circle", binaries: ["agy"]),
        KnownAgent(
            id: "deepseek", name: "DeepSeek TUI", symbol: "water.waves",
            binaries: ["deepseek", "deepseek-tui", "codewhale", "codewhale-tui"], packages: ["deepseek-tui"]),
        KnownAgent(id: "zcode", name: "ZCode", symbol: "z.circle", binaries: ["zcode"]),
        KnownAgent(id: "mimo", name: "MiMo Code", symbol: "m.circle", binaries: ["mimo"], packages: ["@mimo-ai/cli"]),
        KnownAgent(
            id: "pi", name: "Pi", symbol: "p.circle", binaries: ["pi"], packages: ["@mariozechner/pi-coding-agent"]),
        KnownAgent(id: "crush", name: "Crush", symbol: "heart", binaries: ["crush"]),
        KnownAgent(id: "cline", name: "Cline", symbol: "c.circle", binaries: ["cline"], packages: ["cline"]),
        KnownAgent(id: "kiro", name: "Kiro CLI", symbol: "k.circle", binaries: ["kiro-cli"]),
        KnownAgent(
            id: "qwen", name: "Qwen Code", symbol: "q.circle", binaries: ["qwen"], packages: ["@qwen-code/qwen-code"],
            adapterID: "qwen"),
        KnownAgent(id: "qoder", name: "Qoder CLI", symbol: "q.square", binaries: ["qodercli"], adapterID: "qoder"),
        KnownAgent(id: "droid", name: "Droid", symbol: "cpu", binaries: ["droid"], adapterID: "droid"),
        KnownAgent(
            id: "codebuddy", name: "CodeBuddy", symbol: "person.2", binaries: ["codebuddy", "cbc"],
            packages: ["@tencent-ai/codebuddy-code"], adapterID: "codebuddy"),
        KnownAgent(
            id: "kimi", name: "Kimi Code", symbol: "moon", binaries: ["kimi"], modules: ["kimi_cli"], adapterID: "kimi"),
        KnownAgent(id: "grok", name: "Grok", symbol: "bolt.horizontal", binaries: ["grok"], adapterID: "grok"),
        KnownAgent(
            id: "vibe", name: "Mistral Vibe", symbol: "wind", binaries: ["vibe"], modules: ["vibe"], adapterID: "vibe"),
    ]

    /// Agents with no hooks Wisp can install: their rows in Settings are Monitor.
    public static var monitorOnly: [KnownAgent] { all.filter { $0.adapterID == nil } }

    /// Every executable name in the table, for a cheap first pass over the process table.
    public static let binaryNames: Set<String> = Set(all.flatMap(\.binaries))

    /// Interpreters that run an agent's script.
    public static func isLauncher(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["node", "bun", "deno"].contains(name) || name.hasPrefix("python")
    }

    /// The agent a process is, from its name (the process table's, at most 16 characters) and
    /// its arguments; nil when it's none of them.
    public static func match(name: String, arguments: [String]) -> KnownAgent? {
        let executable = arguments.first.map(baseName) ?? name
        if let agent = byBinary(executable) ?? byBinary(name) {
            return agent.accepts(Array(arguments.dropFirst())) ? agent : nil
        }
        guard isLauncher(name) || isLauncher(executable) else { return nil }
        let rest = Array(arguments.dropFirst())
        if let flag = rest.firstIndex(of: "-m"), rest.indices.contains(flag + 1) {
            let module = rest[flag + 1]
            return all.first { $0.modules.contains(module) }
        }
        // The script is the first argument that isn't a flag (`node --no-warnings <script>`).
        // `-c` and `-e` run code given inline, which isn't an agent's script.
        guard let script = rest.first(where: { !$0.hasPrefix("-") }),
            !rest.prefix(while: { $0.hasPrefix("-") })
                .contains(where: { ["-c", "-e", "--eval"].contains($0) })
        else { return nil }
        if let agent = all.first(where: { agent in
            agent.packages.contains { script.contains("/node_modules/\($0)/") }
        }) {
            return agent
        }
        return byBinary(withoutScriptExtension(baseName(script)))
    }

    private static func byBinary(_ name: String) -> KnownAgent? { all.first { $0.binaries.contains(name) } }

    private static func baseName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func withoutScriptExtension(_ name: String) -> String {
        for suffix in [".js", ".mjs", ".cjs", ".py"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// One process that matched an agent.
    public struct Found: Equatable, Sendable {
        public let pid: Int32
        public let parent: Int32
        public let agent: KnownAgent?

        public init(pid: Int32, parent: Int32, agent: KnownAgent?) {
            self.pid = pid
            self.parent = parent
            self.agent = agent
        }
    }

    /// The matches without processes an agent started of itself (a relaunch, a worker), so each
    /// running agent counts once. Order is kept.
    public static func outermost(_ found: [Found]) -> [Found] {
        let agents = Dictionary(found.map { ($0.pid, $0.agent) }, uniquingKeysWith: { first, _ in first })
        return found.filter { $0.agent != nil && agents[$0.parent] != $0.agent }
    }

    /// The `.app` an executable belongs to: the outermost one, so a helper app inside another
    /// app names the main app. Nil outside an app.
    public static func appBundlePath(executable: String) -> String? {
        guard let range = executable.range(of: ".app/") else { return nil }
        return String(executable[..<range.lowerBound]) + ".app"
    }
}

/// A coding agent found running by its process, shown as a Running session with its folder.
public struct MonitoredSession: Equatable, Identifiable, Sendable {
    public let agent: KnownAgent
    public let pid: Int32
    /// Seconds since 1970, so a reused pid reads as a new session.
    public let started: Double
    /// The process's working folder, or empty when it couldn't be read.
    public let cwd: String
    /// Its controlling terminal (`/dev/ttys003`), for bringing the tab forward.
    public let tty: String?
    /// Bundle id of the terminal or editor it runs in, when found.
    public let terminal: String?

    public init(agent: KnownAgent, pid: Int32, started: Double, cwd: String, tty: String?, terminal: String?) {
        self.agent = agent
        self.pid = pid
        self.started = started
        self.cwd = cwd
        self.tty = tty
        self.terminal = terminal
    }

    public var id: String { "\(agent.id)-\(pid)-\(Int(started))" }

    /// The working folder's name, or the agent's when there's none.
    public var project: String {
        let name = (cwd as NSString).lastPathComponent
        return cwd.isEmpty || cwd == "/" || name.isEmpty ? agent.name : name
    }
}

/// `KERN_PROCARGS2`'s buffer: the argument count, the executable path, padding, then the
/// arguments, each ending in a NUL. The environment that follows is never read.
public enum ProcessArguments {
    public static func parse(_ data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let count = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        var index = 4
        // The executable path, then the NULs that pad it.
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < count, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            guard index < bytes.count else { break }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
