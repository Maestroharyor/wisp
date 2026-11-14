/// Command shells by program name. A hook run through one isn't the agent, and a rule
/// never widens past one, since it runs whatever it's given.
public enum ShellNames {
    public static let all: Set<String> = [
        "sh", "bash", "zsh", "dash", "fish", "ksh", "csh", "tcsh", "nu", "pwsh", "xonsh",
    ]
}
