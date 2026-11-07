import Foundation

extension AgentAdapters {
    /// OpenCode has no command hooks, so Wisp installs a small plugin (`OpenCodePlugin`) that
    /// runs the helper on OpenCode's bus events. A permission request waits for the notch while
    /// OpenCode's own prompt stays up; whichever is answered first wins. The plugin answers
    /// through OpenCode's server API, and stops waiting when the terminal answered.
    static let opencode = AgentAdapter(
        source: .opencode, displayName: "OpenCode", symbol: "curlybraces.square", fallbackProject: "OpenCode",
        hookFile: HookFile(
            path: ".config/opencode/plugins/wisp.js", format: .opencodePlugin,
            events: OpenCodeHooks.events, backgroundEvents: [], toolEvents: OpenCodeHooks.toolEvents,
            statusLine: false, helperArguments: " --source opencode"),
        capabilities: [.approve, .compaction, .toolActivity],
        setupNote: nil,
        readEvent: { json, terminal in
            AgentEvent(json: OpenCodeHooks.normalized(json), source: .opencode, terminal: terminal)
        },
        promptFor: { _ in .tool },
        write: { decision in
            switch decision {
            case .allow: OpenCodeHooks.reply(["reply": "once"])
            case .deny(_, let reason):
                // A reason goes to the model as feedback; without one it's the TUI's plain reject.
                reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? OpenCodeHooks.reply(["reply": "reject"])
                    : OpenCodeHooks.reply([
                        "reply": "reject", "message": PermissionReply.denial(for: .tool, reason: reason),
                    ])
            case .answer: nil
            }
        })
}

/// What Wisp's OpenCode plugin sends: an OpenCode bus event's name as `hook_event_name`, the
/// session and folder, and only the fields a label needs. This turns it into the hook fields
/// Claude Code uses, so the common reader takes it.
public enum OpenCodeHooks {
    public static let permissionAsked = "permission.asked"
    public static let questionAsked = "question.asked"
    /// The notification type for a question the agent asks in the terminal.
    public static let question = "opencode_question"
    /// The notification type for an answer from the notch that OpenCode didn't take, so its
    /// own prompt still waits.
    public static let replyFailed = "opencode_reply_failed"

    /// Everything the plugin forwards, as OpenCode names it. `session.compacting` is the
    /// plugin's name for the `experimental.session.compacting` hook, and
    /// `permission.reply_failed` its own for an answer no route took.
    static let events = [
        "session.created", "session.status", "session.deleted", "session.compacting", "session.compacted",
        permissionAsked, "permission.replied", "permission.reply_failed", questionAsked, "question.replied",
        "question.rejected",
    ]
    static let toolEvents = ["tool.execute.before", "tool.execute.after"]

    static func normalized(_ json: JSONValue) -> JSONValue {
        guard case .object(let fields) = json else { return json }
        var out: [String: JSONValue] = [:]
        out["session_id"] = fields["session_id"]
        out["cwd"] = fields["cwd"]
        let name = fields["hook_event_name"]?.stringValue ?? ""
        let kind: AgentEvent.Kind?
        switch name {
        case "session.created": kind = .sessionStart
        case "session.status":
            switch fields["status"]?.stringValue {
            case "busy": kind = .userPromptSubmit
            case "idle": kind = .stop
            default: kind = nil
            }
        case "session.deleted": kind = .sessionEnd
        case "session.compacting": kind = .preCompact
        case "session.compacted": kind = .postCompact
        case permissionAsked:
            kind = .permissionRequest
            let permission = fields["permission"]?.stringValue
            out["tool_name"] = permission.map(JSONValue.string)
            out["tool_use_id"] = fields["request_id"]
            out["tool_input"] = .object(requestInput(permission: permission, fields: fields))
        // Answered in the terminal or the notch: the tool goes ahead (or fails), so a session
        // that showed Needs you is working again. The request id never matches a running tool.
        case "permission.replied", "question.replied", "question.rejected":
            kind = .postToolUse
            out["tool_use_id"] = fields["request_id"]
        case questionAsked:
            kind = .notification
            out["notification_type"] = .string(question)
        case "permission.reply_failed":
            kind = .notification
            out["notification_type"] = .string(replyFailed)
        case "tool.execute.before", "tool.execute.after":
            kind = name == "tool.execute.before" ? .preToolUse : .postToolUse
            out["tool_name"] = fields["tool"]
            out["tool_use_id"] = fields["call_id"]
            out["tool_input"] = .object(toolInput(fields["args"]))
        default: kind = nil
        }
        out["hook_event_name"] = kind.map { .string($0.rawValue) }
        return .object(out)
    }

    /// A permission request's subject from its metadata, or its first pattern (a command
    /// prefix, a path relative to the project, a URL). A bare `*` says nothing.
    private static func requestInput(permission: String?, fields: [String: JSONValue]) -> [String: JSONValue] {
        let metadata = fields["metadata"]
        var pattern: JSONValue?
        if case .array(let patterns) = fields["patterns"], let first = patterns.first?.stringValue, first != "*" {
            pattern = .string(first)
        }
        var input: [String: JSONValue] = [:]
        switch permission {
        case "bash": input["command"] = metadata?["command"] ?? pattern
        case "edit", "read", "external_directory": input["file_path"] = metadata?["filepath"] ?? pattern
        case "webfetch": input["url"] = metadata?["url"] ?? pattern
        case "task":
            input["description"] = metadata?["description"]
            input["subagent_type"] = metadata?["subagent_type"] ?? pattern
        default: input["description"] = pattern
        }
        return input
    }

    /// OpenCode's tool arguments under Claude Code's names (`filePath` is `file_path`).
    private static func toolInput(_ args: JSONValue?) -> [String: JSONValue] {
        var input: [String: JSONValue] = [:]
        for (from, to) in [
            ("command", "command"), ("filePath", "file_path"), ("pattern", "pattern"), ("url", "url"),
            ("query", "query"), ("description", "description"), ("subagent_type", "subagent_type"),
        ] {
            input[to] = args?[from]
        }
        return input
    }

    /// The helper's stdout for the plugin: OpenCode's own reply body (`once` or `reject`, and
    /// an optional message).
    static func reply(_ fields: [String: String]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(fields)).map { String(decoding: $0, as: UTF8.self) }
    }
}

/// The plugin file Wisp writes for OpenCode. The hook command is a JSON string on one line
/// (`const COMMAND = "..."`), so Wisp can read back which helper it calls and how long it waits.
public enum OpenCodePlugin {
    private static let commandPrefix = "const COMMAND = "
    private static let toolsOn = "const TOOLS = true"

    /// The whole file, for `command` (`HookInstaller.command`) with or without tool activity.
    public static func source(command: String, tools: Bool) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let literal = (try? encoder.encode(command)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        let text =
            template
            .replacingOccurrences(of: "__COMMAND__", with: literal)
            .replacingOccurrences(of: "__TOOLS__", with: tools ? "true" : "false")
        return Data(text.utf8)
    }

    /// The hook command in a plugin file; nil when there's no such line.
    public static func command(in data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(commandPrefix) }) else { return nil }
        return try? JSONDecoder().decode(String.self, from: Data(line.dropFirst(commandPrefix.count).utf8))
    }

    public static func toolsOn(in data: Data) -> Bool {
        String(decoding: data, as: UTF8.self).split(separator: "\n").contains { $0 == toolsOn }
    }

    /// Like `HookInstaller.link` for a settings file: whether the plugin calls this copy's
    /// helper with `timeout`, and is this version's file.
    static func link(in data: Data, helper: String, file: HookFile, timeout: Int) -> HookLink {
        if data.isEmpty { return .none }
        guard let installed = command(in: data), installed.contains(HookInstaller.helperName) else { return .other }
        let base = HookInstaller.command(helper: helper, file: file)
        guard HookInstaller.withoutTimeout(installed) == base else { return .other }
        let mine = HookInstaller.command(helper: helper, file: file, timeout: timeout)
        return data == source(command: mine, tools: toolsOn(in: data)) ? .this : .outdated
    }

    /// The approval wait the plugin's command carries; nil without a plugin.
    static func approvalTimeout(in data: Data) -> Int? {
        guard let installed = command(in: data) else { return nil }
        let words = installed.split(separator: " ").map(String.init)
        return HookInstaller.timeout(arguments: words) ?? HookInstaller.approvalTimeout
    }

    // Plain JavaScript, no imports beyond Node's, so it loads in OpenCode's Bun runtime with no
    // package install. It uses the v1 plugin API (`@opencode-ai/plugin` 1.19): an exported
    // function taking `{ client, directory }` and returning hooks. OpenCode never calls the
    // `permission.ask` hook in 1.19, so requests are answered through its server API.
    private static let template = """
        // Wisp's OpenCode plugin. Wisp writes this file and replaces it when it updates;
        // disconnect OpenCode in Wisp's Settings > Agents to remove it.
        // It hands session events to Wisp's helper and answers permission requests from the
        // notch. It sends ids, the folder, tool names and the command, file or address a request
        // is about, never prompts, messages, diffs or file contents.
        import { spawn } from "node:child_process"

        const COMMAND = __COMMAND__
        const TOOLS = __TOOLS__
        // Fields worth a label; everything else in a tool call or request stays in OpenCode.
        const ARGS = ["command", "filePath", "pattern", "url", "query", "description", "subagent_type"]
        const METADATA = ["command", "filepath", "url", "description", "subagent_type"]

        function pick(value, keys) {
          const out = {}
          if (!value || typeof value !== "object") return out
          for (const key of keys) if (typeof value[key] === "string") out[key] = value[key]
          return out
        }

        export const WispPlugin = async ({ client, directory }) => {
          // Subagent sessions, by the session they work for: their requests show under it.
          const parents = new Map()
          const busy = new Set()
          // Helpers holding a permission request for the notch, by request id.
          const waiting = new Map()
          const owner = (id) => parents.get(id) ?? id

          function run(payload, answer) {
            let child
            try {
              child = spawn("/bin/sh", ["-c", "exec " + COMMAND], {
                stdio: ["pipe", answer ? "pipe" : "ignore", "ignore"],
              })
            } catch {
              return { child: undefined, done: Promise.resolve("") }
            }
            const done = new Promise((resolve) => {
              let out = ""
              if (child.stdout) {
                child.stdout.setEncoding("utf8")
                child.stdout.on("data", (chunk) => {
                  out += chunk
                })
              }
              child.on("error", () => resolve(""))
              child.on("close", () => resolve(out))
            })
            child.stdin.on("error", () => {})
            child.stdin.end(JSON.stringify({ ...payload, cwd: directory }))
            return { child, done }
          }

          const send = (payload) => {
            run(payload, false)
          }

          // Requests OpenCode says were answered, so a late answer from the notch isn't a failure.
          const replied = new Set()
          const accepted = (result) => !!result && result.data === true

          // True once OpenCode took the answer. The public client method first, then the same
          // route through the client's request function (v1 clients have no method for it),
          // then the older session route, which has no reason.
          async function reply(sessionID, requestID, decision) {
            const body = { reply: decision.reply }
            if (typeof decision.message === "string" && decision.message) body.message = decision.message
            const routes = [
              () =>
                client.permission && typeof client.permission.reply === "function"
                  ? client.permission.reply({ requestID, ...body })
                  : undefined,
              () =>
                client._client && typeof client._client.post === "function"
                  ? client._client.post({
                      url: "/permission/{requestID}/reply",
                      path: { requestID },
                      body,
                      headers: { "Content-Type": "application/json" },
                    })
                  : undefined,
              () =>
                typeof client.postSessionIdPermissionsPermissionId === "function"
                  ? client.postSessionIdPermissionsPermissionId({
                      path: { id: sessionID, permissionID: requestID },
                      body: { response: decision.reply },
                    })
                  : undefined,
            ]
            for (const route of routes) {
              try {
                if (accepted(await route())) return true
              } catch {}
            }
            return false
          }

          async function ask(request) {
            const patterns = Array.isArray(request.patterns) ? request.patterns : []
            const { child, done } = run(
              {
                hook_event_name: "permission.asked",
                session_id: owner(request.sessionID),
                request_id: request.id,
                permission: request.permission,
                patterns: patterns.filter((pattern) => typeof pattern === "string").slice(0, 1),
                metadata: pick(request.metadata, METADATA),
              },
              true,
            )
            if (child) waiting.set(request.id, child)
            const text = await done
            // Gone already: answered in the terminal, so the notch's answer is too late.
            if (!waiting.delete(request.id)) return
            let decision
            try {
              decision = JSON.parse(text)
            } catch {
              return
            }
            if (!decision || (decision.reply !== "once" && decision.reply !== "reject")) return
            if (await reply(request.sessionID, request.id, decision)) return
            // OpenCode's own prompt still waits: tell Wisp, so the session shows Needs you.
            if (!replied.has(request.id)) {
              send({
                hook_event_name: "permission.reply_failed",
                session_id: owner(request.sessionID),
                request_id: request.id,
              })
            }
          }

          function onEvent(event) {
            const props = event.properties || {}
            const id = props.sessionID || (props.info && props.info.id)
            if (typeof id !== "string") return
            const name = event.type
            switch (name) {
              case "session.created":
                if (props.info && props.info.parentID) {
                  parents.set(id, owner(props.info.parentID))
                  return
                }
                return send({ hook_event_name: name, session_id: id })
              case "session.status": {
                if (parents.has(id)) return
                const status = props.status && props.status.type
                // Busy comes again after a retry; only the first one starts a turn.
                if (status === "busy" && !busy.has(id)) {
                  busy.add(id)
                  return send({ hook_event_name: name, session_id: id, status })
                }
                if (status === "idle") {
                  busy.delete(id)
                  return send({ hook_event_name: name, session_id: id, status })
                }
                return
              }
              case "session.deleted":
                busy.delete(id)
                if (parents.delete(id)) return
                return send({ hook_event_name: name, session_id: id })
              case "session.compacted":
                if (parents.has(id)) return
                return send({ hook_event_name: name, session_id: id })
              case "permission.asked":
                return ask(props)
              case "permission.replied": {
                replied.add(props.requestID)
                const child = waiting.get(props.requestID)
                if (child) {
                  waiting.delete(props.requestID)
                  child.kill()
                }
                return send({ hook_event_name: name, session_id: owner(id), request_id: props.requestID })
              }
              case "question.asked":
                return send({ hook_event_name: name, session_id: owner(id), request_id: props.id })
              case "question.replied":
              case "question.rejected":
                return send({ hook_event_name: name, session_id: owner(id), request_id: props.requestID })
            }
          }

          // Every hook swallows its own errors: Wisp must never break OpenCode.
          const hooks = {
            event: async ({ event }) => {
              try {
                await onEvent(event)
              } catch {}
            },
            "experimental.session.compacting": async (input) => {
              try {
                if (input && !parents.has(input.sessionID)) {
                  send({ hook_event_name: "session.compacting", session_id: input.sessionID })
                }
              } catch {}
            },
          }
          if (TOOLS) {
            hooks["tool.execute.before"] = async (input, output) => {
              try {
                send({
                  hook_event_name: "tool.execute.before",
                  session_id: owner(input.sessionID),
                  tool: input.tool,
                  call_id: input.callID,
                  args: pick(output && output.args, ARGS),
                })
              } catch {}
            }
            hooks["tool.execute.after"] = async (input) => {
              try {
                send({
                  hook_event_name: "tool.execute.after",
                  session_id: owner(input.sessionID),
                  tool: input.tool,
                  call_id: input.callID,
                  args: pick(input.args, ARGS),
                })
              } catch {}
            }
          }
          return hooks
        }

        """
}
