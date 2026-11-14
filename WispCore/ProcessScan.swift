import Darwin
import Foundation

/// Finds the coding agents in `KnownAgents` running in a terminal, from the process table: the
/// same `sysctl` read `AgentProcess` uses, then each candidate's arguments (`KERN_PROCARGS2`) and
/// working folder (`proc_pidinfo`, public libproc). Only this user's processes with a
/// controlling terminal count, and arguments are read only for processes whose name is an
/// agent's or a launcher's, so a scan costs one table read and a handful of small calls. Nothing
/// from another process's environment is read.
public enum ProcessScan {
    /// The agents running now, each once.
    public static func sessions() -> [MonitoredSession] {
        let entries = userProcesses()
        let byPID = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let found = entries.compactMap { entry -> KnownAgents.Found? in
            guard entry.tty != nil, KnownAgents.binaryNames.contains(entry.name) || KnownAgents.isLauncher(entry.name)
            else { return nil }
            let agent = KnownAgents.match(name: entry.name, arguments: arguments(of: entry.pid) ?? [])
            return agent.map { KnownAgents.Found(pid: entry.pid, parent: entry.parent, agent: $0) }
        }
        return KnownAgents.outermost(found).compactMap { match in
            guard let agent = match.agent, let entry = byPID[match.pid] else { return nil }
            return MonitoredSession(
                agent: agent, pid: entry.pid, started: entry.started, cwd: workingFolder(of: entry.pid) ?? "",
                tty: entry.tty, terminal: terminalApp(above: entry.parent, in: byPID))
        }
    }

    struct Entry {
        let pid: Int32
        let parent: Int32
        let name: String
        let started: Double
        let tty: String?
    }

    /// This user's live processes.
    static func userProcesses() -> [Entry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Room for processes started between the two calls.
        size += size / 8
        var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, u_int(mib.count), &entries, &size, nil, 0) == 0 else { return [] }
        return entries.prefix(size / MemoryLayout<kinfo_proc>.stride).compactMap { entry in
            guard entry.kp_proc.p_stat != SZOMB, entry.kp_proc.p_pid > 0 else { return nil }
            let name = withUnsafeBytes(of: entry.kp_proc.p_comm) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            let start = entry.kp_proc.p_un.__p_starttime
            let device = entry.kp_eproc.e_tdev
            // NODEV: no controlling terminal.
            let deviceName = device == -1 ? nil : devname(device, S_IFCHR).map { String(cString: $0) }
            return Entry(
                pid: entry.kp_proc.p_pid, parent: entry.kp_eproc.e_ppid, name: name,
                started: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000,
                tty: TerminalContext.ttyPath(deviceName: deviceName))
        }
    }

    /// This user's live processes, for `BashChild`.
    public static func processTable() -> [BashChild.Entry] {
        userProcesses().map { BashChild.Entry(pid: $0.pid, parent: $0.parent, started: $0.started) }
    }

    /// The process's arguments; nil when they can't be read.
    public static func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcessArguments.parse(Data(buffer.prefix(size)))
    }

    /// The process's working folder; nil when it can't be read.
    static func workingFolder(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// The bundle id of the first app above the agent (the terminal or editor it runs in).
    static func terminalApp(above pid: Int32, in table: [Int32: Entry]) -> String? {
        var current = pid
        for _ in 0..<AgentProcess.maxSteps {
            guard current > 1, let entry = table[current] else { return nil }
            if let path = executablePath(of: current), let app = KnownAgents.appBundlePath(executable: path) {
                return Bundle(path: app)?.bundleIdentifier
            }
            current = entry.parent
        }
        return nil
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
