import Foundation

/// Where Wisp's agent hooks lead.
public enum HookLink: Equatable, Sendable {
    case none
    case this
    /// This copy's hooks, from an older version: some events Wisp now uses are missing.
    case outdated
    case other
}

/// Adds and removes Wisp's hooks in an agent's hook file (`HookFile`): Claude Code's
/// settings.json, Codex's hooks.json or Gemini CLI's settings.json, which share the `hooks` shape. The user's own
/// settings and hooks are left alone. Wisp's entries are recognised by the helper's name. OpenCode's
/// plugin is a file of Wisp's own (`OpenCodePlugin`), written whole.
public enum HookInstaller {
    public enum Failure: Error { case notAnObject }

    public static let helperName = "wisp-agent"
    public static let events = AgentSource.claude.hookEvents
    /// Seconds a permission prompt waits for the notch before the agent shows its own, unless
    /// phone push asks for longer (`approvalTimeout(push:minutes:)`).
    public static let approvalTimeout = 120
    /// The helper's flag for a longer wait. Left out at the default, so hooks installed before
    /// it existed still read as current.
    public static let timeoutFlag = "--timeout"
    /// The helper outlives the hook's own timeout by this much, so the agent gives up first.
    public static let helperGrace = 5
    /// The notch hands a request back this long before the hook times out, so the agent can
    /// still show its own prompt.
    public static let handBackMargin = 10
    /// Bounds for the approval wait while push is on, in minutes.
    public static let pushTimeoutMinutes = 2...60
    public static let defaultPushTimeoutMinutes = 10

    /// The PermissionRequest hook's timeout in seconds: the default, or `minutes` while push is on.
    public static func approvalTimeout(push: Bool, minutes: Int) -> Int {
        guard push else { return approvalTimeout }
        return min(max(minutes, pushTimeoutMinutes.lowerBound), pushTimeoutMinutes.upperBound) * 60
    }

    /// `tools` adds the tool activity hooks too; without it they're taken out.
    public static func install(
        into settings: Data, command: String, source: AgentSource = .claude, tools: Bool = false
    ) throws -> Data {
        try install(into: settings, command: command, file: source.adapter.hookFile, tools: tools)
    }

    /// `timeout` is the PermissionRequest hook's, in seconds; pass the same one to `command`.
    public static func install(
        into settings: Data, command: String, file: HookFile, tools: Bool = false, timeout: Int = approvalTimeout
    ) throws -> Data {
        // A plugin is Wisp's own file, written whole.
        if file.format.isPlugin { return OpenCodePlugin.source(command: command, tools: tools) }
        var root = try object(settings)
        var hooks = stripped(root["hooks"])
        for event in file.events + (tools ? file.toolEvents : []) {
            let seconds = event == "PermissionRequest" ? timeout : 5
            let scaled = seconds * file.format.timeoutScale
            var handler: [String: JSONValue] = [
                "type": .string("command"), "command": .string(command), "timeout": .number(Double(scaled)),
            ]
            if file.backgroundEvents.contains(event) { handler["async"] = .bool(true) }
            let group: JSONValue = .object(["matcher": .string(""), "hooks": .array([.object(handler)])])
            var groups: [JSONValue] = []
            if case .array(let existing) = hooks[event] { groups = existing }
            hooks[event] = .array(groups + [group])
        }
        root["hooks"] = .object(hooks)
        return try encode(.object(root))
    }

    public static func remove(from settings: Data) throws -> Data {
        var root = try object(settings)
        let hooks = stripped(root["hooks"])
        root["hooks"] = hooks.isEmpty ? nil : .object(hooks)
        return try encode(.object(root))
    }

    /// The hook command for `helper`: the path in POSIX single quotes, tagged with the agent
    /// unless it's the default.
    public static func command(helper: String, source: AgentSource) -> String {
        command(helper: helper, file: source.adapter.hookFile)
    }

    /// A `timeout` other than the default is passed on, so the helper waits as long as the hook.
    /// An agent Wisp never answers (monitor only) gets no wait, so push never makes it outdated.
    public static func command(helper: String, file: HookFile, timeout: Int = approvalTimeout) -> String {
        let wait = timeout == approvalTimeout || !file.waitsForApproval ? "" : " \(timeoutFlag) \(timeout)"
        return quote(helper) + file.helperArguments + wait
    }

    /// The helper's `--timeout` from its arguments; nil when absent or not a positive number.
    public static func timeout(arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: timeoutFlag), arguments.indices.contains(index + 1),
            let seconds = Int(arguments[index + 1]), seconds > 0
        else { return nil }
        return seconds
    }

    /// The approval wait Wisp's hooks in `file` were installed with: the PermissionRequest hook's
    /// timeout, or the wait in a plugin's command. Nil when there's neither.
    public static func installedApprovalTimeout(in settings: Data, file: HookFile) throws -> Int? {
        file.format.isPlugin ? OpenCodePlugin.approvalTimeout(in: settings) : try installedApprovalTimeout(in: settings)
    }

    /// The PermissionRequest timeout Wisp's hook in `settings` was installed with; nil when
    /// there's no such hook.
    public static func installedApprovalTimeout(in settings: Data) throws -> Int? {
        let root = try object(settings)
        guard case .array(let groups) = hooksObject(root["hooks"])["PermissionRequest"] else { return nil }
        for group in groups {
            guard case .array(let handlers) = group["hooks"] else { continue }
            if let seconds = handlers.first(where: isWisp)?["timeout"]?.intValue { return seconds }
        }
        return nil
    }

    /// `text` as one POSIX shell word in single quotes.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The inverse of `quote`: single-quoted runs joined by `\'`. Anything else is nil.
    public static func unquote(_ word: String) -> String? {
        var result = ""
        var rest = Substring(word)
        while !rest.isEmpty {
            if rest.hasPrefix("\\'") {
                result += "'"
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("'") {
                let body = rest.dropFirst()
                guard let end = body.firstIndex(of: "'") else { return nil }
                result += body[..<end]
                rest = body[body.index(after: end)...]
            } else {
                return nil
            }
        }
        return result
    }

    /// Whether the hooks call this copy's helper, another copy's (a dev build, a moved app),
    /// or no Wisp at all. Another copy's helper talks to that copy, so this one hears nothing.
    public static func link(
        in settings: Data, helper: String, source: AgentSource, timeout: Int = approvalTimeout
    ) throws -> HookLink {
        try link(in: settings, helper: helper, file: source.adapter.hookFile, timeout: timeout)
    }

    /// `timeout` is the approval wait Wisp wants now. This copy's hooks with another one (push
    /// was turned on or off since) read as outdated, not as another copy's.
    public static func link(
        in settings: Data, helper: String, file: HookFile, timeout: Int = approvalTimeout
    ) throws -> HookLink {
        if file.format.isPlugin {
            return OpenCodePlugin.link(in: settings, helper: helper, file: file, timeout: timeout)
        }
        let commands = try wispCommands(in: settings)
        if commands.isEmpty { return .none }
        let base = command(helper: helper, file: file)
        guard commands.allSatisfy({ withoutTimeout($0.command) == base }) else { return .other }
        let mine = command(helper: helper, file: file, timeout: timeout)
        let installed = Set(commands.map(\.event))
        let events = Set(file.events)
        let current = installed == events || installed == events.union(file.toolEvents)
        return current && commands.allSatisfy({ $0.command == mine }) ? .this : .outdated
    }

    /// A hook command without a trailing ` --timeout <seconds>`.
    static func withoutTimeout(_ command: String) -> String {
        guard let range = command.range(of: " \(timeoutFlag) ", options: .backwards) else { return command }
        let seconds = command[range.upperBound...]
        guard !seconds.isEmpty, seconds.allSatisfy(\.isASCII), seconds.allSatisfy(\.isNumber) else { return command }
        return String(command[..<range.lowerBound])
    }

    /// Whether Wisp's tool activity hooks are in the file.
    public static func toolsInstalled(in settings: Data, file: HookFile = AgentSource.claude.adapter.hookFile) throws
        -> Bool
    {
        if file.format.isPlugin { return OpenCodePlugin.toolsOn(in: settings) }
        let events = Set(try wispCommands(in: settings).map(\.event))
        return !events.isDisjoint(with: file.toolEvents)
    }

    public static func isInstalled(in settings: Data) throws -> Bool {
        try !wispCommands(in: settings).isEmpty
    }

    private static func wispCommands(in settings: Data) throws -> [(event: String, command: String)] {
        let root = try object(settings)
        return hooksObject(root["hooks"]).flatMap { event, value -> [(event: String, command: String)] in
            guard case .array(let groups) = value else { return [] }
            return groups.flatMap { group -> [(event: String, command: String)] in
                guard case .array(let handlers) = group["hooks"] else { return [] }
                return handlers.filter(isWisp).compactMap { handler in
                    handler["command"]?.stringValue.map { (event, $0) }
                }
            }
        }
    }

    private static func isWisp(_ handler: JSONValue) -> Bool {
        handler["command"]?.stringValue?.contains(helperName) ?? false
    }

    /// The hooks object minus Wisp's handlers, dropping groups and events that only held
    /// Wisp's. The user's own empty entries stay as they were.
    private static func stripped(_ hooks: JSONValue?) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (event, value) in hooksObject(hooks) {
            guard case .array(let groups) = value else {
                result[event] = value
                continue
            }
            let kept = groups.compactMap(strippedGroup)
            if !kept.isEmpty || groups.isEmpty { result[event] = .array(kept) }
        }
        return result
    }

    private static func strippedGroup(_ group: JSONValue) -> JSONValue? {
        guard case .object(var fields) = group, case .array(let handlers) = fields["hooks"] else { return group }
        let kept = handlers.filter { !isWisp($0) }
        if kept.isEmpty, !handlers.isEmpty { return nil }
        fields["hooks"] = .array(kept)
        return .object(fields)
    }

    private static func hooksObject(_ value: JSONValue?) -> [String: JSONValue] {
        if case .object(let hooks) = value { return hooks }
        return [:]
    }

    private static func object(_ data: Data) throws -> [String: JSONValue] {
        guard let root = try SettingsJSON.object(data) else { throw Failure.notAnObject }
        return root
    }

    private static func encode(_ value: JSONValue) throws -> Data {
        try SettingsJSON.encode(value)
    }
}
