/// Command shells by program name. A hook run through one isn't the agent, and a rule
/// never widens past one, since it runs whatever it's given.
public enum ShellNames {
    public static let all: Set<String> = [
        "sh", "bash", "zsh", "dash", "fish", "ksh", "csh", "tcsh", "nu", "pwsh", "xonsh",
    ]

    /// Whether a process is a shell, from its process table name and, for Python, its
    /// arguments: xonsh is a Python program, so it usually runs as `python <path>/xonsh` or
    /// `python -m xonsh`. A login shell's name starts with "-". `arguments` is read only for Python.
    public static func isShell(name: String, arguments: @autoclosure () -> [String]?) -> Bool {
        let name = name.hasPrefix("-") ? String(name.dropFirst()) : name
        if all.contains(name) { return true }
        guard name.lowercased().hasPrefix("python"), let arguments = arguments() else { return false }
        let rest = Array(arguments.dropFirst())
        if let flag = rest.firstIndex(of: "-m") { return rest.indices.contains(flag + 1) && rest[flag + 1] == "xonsh" }
        // The script is the first argument that isn't a flag; `-c` runs code given inline instead.
        let flags = rest.prefix { $0.hasPrefix("-") }
        guard !flags.contains("-c"), let script = rest.first(where: { !$0.hasPrefix("-") }) else { return false }
        let base = script.split(separator: "/").last.map(String.init) ?? script
        return base == "xonsh" || base == "xonsh.py"
    }
}
