import Darwin

/// The coding agent's own process, so a session can end when the agent quits without a
/// SessionEnd hook (a closed terminal tab, a crash, `kill`). The start time tells a reused
/// pid apart from the original.
public struct AgentProcess: Equatable, Sendable {
    public let pid: Int32
    /// Seconds since 1970, as the kernel reports it.
    public let started: Double

    public init(pid: Int32, started: Double) {
        self.pid = pid
        self.started = started
    }

    /// What the process table says about one process.
    public struct Info: Equatable, Sendable {
        public let parent: Int32
        public let name: String
        public let started: Double

        public init(parent: Int32, name: String, started: Double) {
            self.parent = parent
            self.name = name
            self.started = started
        }
    }

    /// Agents may run a hook command through a shell, which isn't the agent.
    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]
    static let maxSteps = 8

    /// The first process at or above `pid` that isn't a shell; nil when there's none below launchd.
    public static func owner(from pid: Int32, info: (Int32) -> Info?) -> AgentProcess? {
        var current = pid
        for _ in 0..<maxSteps {
            guard current > 1, let process = info(current) else { return nil }
            // A login shell's name starts with "-".
            let name = process.name.hasPrefix("-") ? String(process.name.dropFirst()) : process.name
            if !shells.contains(name) { return AgentProcess(pid: current, started: process.started) }
            current = process.parent
        }
        return nil
    }

    public func isRunning(info: (Int32) -> Info?) -> Bool { info(pid)?.started == started }

    /// The process table entry for `pid`, or nil when there's no such live process. Zombies
    /// (exited, not yet reaped) count as gone.
    public static func systemInfo(_ pid: Int32) -> Info? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var entry = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &entry, &size, nil, 0) == 0, size > 0, entry.kp_proc.p_pid == pid,
            entry.kp_proc.p_stat != SZOMB
        else { return nil }
        let name = withUnsafeBytes(of: entry.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let start = entry.kp_proc.p_un.__p_starttime
        return Info(
            parent: entry.kp_eproc.e_ppid, name: name,
            started: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    /// The agent that ran this process (the helper), from the process table.
    public static func ownerOfThisProcess() -> AgentProcess? { owner(from: getppid(), info: systemInfo) }

    var json: JSONValue { .object(["pid": .number(Double(pid)), "started": .number(started)]) }

    init?(json: JSONValue?) {
        guard let pid = json?["pid"]?.intValue, let started = json?["started"]?.doubleValue else { return nil }
        self.init(pid: Int32(clamping: pid), started: started)
    }
}
