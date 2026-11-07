import XCTest

@testable import WispCore

/// Runs the plugin Wisp writes for OpenCode under Node, with a stand-in helper and OpenCode
/// client, on events shaped like OpenCode v1.19.5's bus events (`packages/schema/src/v1`).
/// Skipped where Node isn't installed. Everything lives in a temporary folder.
final class OpenCodePluginScriptTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "wisp-opencode-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func node() throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates =
            path.split(separator: ":").map { String($0) + "/node" } + ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        guard let found = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("Node isn't installed")
        }
        return URL(fileURLWithPath: found)
    }

    /// Logs what it's given, and answers permission requests the way Wisp would.
    private let helperScript = """
        #!/bin/sh
        input=$(cat)
        printf '%s\\n' "$input" >> "$(dirname "$0")/log.jsonl"
        case "$input" in
          *'"per_deny"'*) printf '{"message":"Denied from the Wisp notch: no","reply":"reject"}' ;;
          *'"per_wait"'*) exec sleep 30 ;;
          *'"permission.asked"'*) printf '{"reply":"once"}' ;;
        esac

        """

    /// argv: the plugin's URL, the log's path, how many payloads to wait for, and `v1` for a
    /// client without the public `permission.reply` method.
    private let harness = """
        import { readFileSync } from "node:fs"
        const [pluginURL, logPath, expected, flavour] = process.argv.slice(2)
        const plugin = await import(pluginURL)
        const calls = []
        // per_ok is taken by the first route there is; per_deny only by the session route;
        // per_fail by none.
        const takes = (route, id) => id === "per_ok" || (id === "per_deny" && route === "session")
        const answer = (route, id) => (takes(route, id) ? { data: true } : { error: { name: "NotFound" } })
        const client = {
          _client: {
            post: async (options) => {
              calls.push({ route: "raw", id: options.path.requestID, body: options.body })
              return answer("raw", options.path.requestID)
            },
          },
          postSessionIdPermissionsPermissionId: async (options) => {
            calls.push({ route: "session", id: options.path.permissionID, session: options.path.id, body: options.body })
            return answer("session", options.path.permissionID)
          },
        }
        if (flavour !== "v1") {
          client.permission = {
            reply: async (options) => {
              const { requestID, ...body } = options
              calls.push({ route: "public", id: requestID, body })
              return answer("public", requestID)
            },
          }
        }
        const lines = () => {
          try {
            return readFileSync(logPath, "utf8").split("\\n").filter((line) => line.length > 0)
          } catch {
            return []
          }
        }
        async function until(check) {
          const end = Date.now() + 10000
          while (!check() && Date.now() < end) await new Promise((resolve) => setTimeout(resolve, 25))
        }

        const hooks = await plugin.WispPlugin({ client, directory: "/Users/me/site" })
        const fire = (type, properties) => hooks.event({ event: { id: "evt_1", type, properties } })
        const info = (id, parentID) => ({ id, slug: "s", projectID: "p", directory: "/Users/me/site", parentID,
          title: "Secret title", version: "1.19.5", time: { created: 1, updated: 1 } })

        // Broken input never throws out of a hook.
        await hooks.event({ event: null })
        await hooks["experimental.session.compacting"](undefined, undefined)
        if (hooks["tool.execute.before"]) await hooks["tool.execute.before"](undefined, undefined)

        await fire("session.created", { sessionID: "ses_1", info: info("ses_1") })
        await fire("session.created", { sessionID: "ses_child", info: info("ses_child", "ses_1") })
        await fire("session.status", { sessionID: "ses_1", status: { type: "busy" } })
        await fire("session.status", { sessionID: "ses_1", status: { type: "retry", attempt: 1, message: "x", next: 1 } })
        await fire("session.status", { sessionID: "ses_1", status: { type: "busy" } })
        await fire("session.status", { sessionID: "ses_child", status: { type: "busy" } })
        await fire("message.part.updated", { sessionID: "ses_1", part: { type: "text", text: "Secret reply" } })
        const asked = [
          fire("permission.asked", { id: "per_ok", sessionID: "ses_child", permission: "bash", patterns: ["npm test"],
            metadata: { command: "npm test" }, always: ["npm *"], tool: { messageID: "msg_1", callID: "call_1" } }),
          fire("permission.asked", { id: "per_deny", sessionID: "ses_1", permission: "edit", patterns: ["src/a.ts"],
            metadata: { filepath: "/Users/me/site/src/a.ts", diff: "Secret diff" }, always: ["*"] }),
          fire("permission.asked", { id: "per_fail", sessionID: "ses_1", permission: "bash", patterns: ["ls"],
            metadata: { command: "ls" }, always: ["ls *"] }),
          fire("permission.asked", { id: "per_wait", sessionID: "ses_1", permission: "webfetch",
            patterns: ["https://example.com"], metadata: { url: "https://example.com" }, always: ["*"] }),
        ]
        // Answered in the terminal once the helper holds it.
        await until(() => lines().some((line) => line.includes('"per_wait"')))
        await fire("permission.replied", { sessionID: "ses_1", requestID: "per_wait", reply: "once" })
        await Promise.all(asked)
        await fire("question.asked", { id: "que_1", sessionID: "ses_1",
          questions: [{ question: "Secret question", header: "h", options: [] }] })
        await fire("question.replied", { sessionID: "ses_1", requestID: "que_1", answers: [["Secret answer"]] })
        await hooks["experimental.session.compacting"]({ sessionID: "ses_1" }, { context: [] })
        await fire("session.compacted", { sessionID: "ses_1" })
        if (hooks["tool.execute.before"]) {
          await hooks["tool.execute.before"]({ tool: "write", sessionID: "ses_child", callID: "c1" },
            { args: { filePath: "/Users/me/site/a.ts", content: "Secret content" } })
          await hooks["tool.execute.after"]({ tool: "write", sessionID: "ses_1", callID: "c1",
            args: { filePath: "/Users/me/site/a.ts", content: "Secret content" } },
            { title: "", output: "Secret output", metadata: {} })
        }
        await fire("session.status", { sessionID: "ses_1", status: { type: "idle" } })
        await fire("session.deleted", { sessionID: "ses_1", info: info("ses_1") })
        await until(() => lines().length >= Number(expected))
        console.log(JSON.stringify(calls))

        """

    private struct Run {
        let sent: [[String: JSONValue]]
        let calls: [[String: JSONValue]]
        let log: String
    }

    private func run(tools: Bool, expected: Int, v1Client: Bool = false) throws -> Run {
        let node = try node()
        let helper = folder.appendingPathComponent(HookInstaller.helperName)
        try Data(helperScript.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let file = AgentSource.opencode.adapter.hookFile
        let command = HookInstaller.command(helper: helper.path, file: file)
        let pluginURL = folder.appendingPathComponent("wisp.mjs")
        try HookInstaller.install(into: Data(), command: command, file: file, tools: tools).write(to: pluginURL)
        let harnessURL = folder.appendingPathComponent("harness.mjs")
        try Data(harness.utf8).write(to: harnessURL)
        let logURL = folder.appendingPathComponent("log.jsonl")

        let process = Process()
        process.executableURL = node
        process.arguments = [
            harnessURL.path, pluginURL.absoluteString, logURL.path, String(expected), v1Client ? "v1" : "v2",
        ]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let lines = try log.split(separator: "\n").map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        let sent = lines.compactMap { value -> [String: JSONValue]? in
            if case .object(let fields) = value { return fields }
            return nil
        }
        XCTAssertEqual(sent.count, lines.count, "every payload is an object")
        guard case .array(let list) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            return Run(sent: sent, calls: [], log: log)
        }
        let calls = list.compactMap { value -> [String: JSONValue]? in
            if case .object(let fields) = value { return fields }
            return nil
        }
        return Run(sent: sent, calls: calls, log: log)
    }

    private func names(_ run: Run) -> [String] {
        run.sent.compactMap { $0["hook_event_name"]?.stringValue }.sorted()
    }

    private func routes(_ run: Run, id: String) -> [String] {
        run.calls.filter { $0["id"] == .string(id) }.compactMap { $0["route"]?.stringValue }
    }

    private static let sessionEvents = [
        "permission.asked", "permission.asked", "permission.asked", "permission.asked", "permission.replied",
        "permission.reply_failed", "question.asked", "question.replied", "session.compacted", "session.compacting",
        "session.created", "session.deleted", "session.status", "session.status",
    ]

    func testPluginForwardsSessionEventsAndAnswersRequests() throws {
        let result = try run(tools: false, expected: Self.sessionEvents.count)
        XCTAssertEqual(names(result), Self.sessionEvents)
        XCTAssertTrue(result.sent.allSatisfy { $0["cwd"] == .string("/Users/me/site") })
        XCTAssertTrue(
            result.sent.allSatisfy { $0["session_id"] == .string("ses_1") },
            "the subagent's request shows under its parent")
        let statuses = result.sent.filter { $0["hook_event_name"] == .string("session.status") }.compactMap {
            $0["status"]?.stringValue
        }
        XCTAssertEqual(Set(statuses), ["busy", "idle"], "one busy per turn, retries left out")

        let edit = try XCTUnwrap(result.sent.first { $0["request_id"] == .string("per_deny") })
        XCTAssertEqual(edit["permission"], .string("edit"))
        XCTAssertEqual(edit["metadata"], .object(["filepath": .string("/Users/me/site/src/a.ts")]))
        XCTAssertEqual(edit["patterns"], .array([.string("src/a.ts")]))
        for secret in ["Secret diff", "Secret question", "Secret answer", "Secret title", "Secret reply"] {
            XCTAssertFalse(result.log.contains(secret), secret)
        }

        // The public method answers first; a route that doesn't take the answer passes it on,
        // down to the session route, which has no reason.
        XCTAssertEqual(routes(result, id: "per_ok"), ["public"])
        XCTAssertEqual(routes(result, id: "per_deny"), ["public", "raw", "session"])
        let reason: JSONValue = .object([
            "reply": .string("reject"), "message": .string("Denied from the Wisp notch: no"),
        ])
        XCTAssertTrue(result.calls.contains { $0["route"] == .string("public") && $0["body"] == reason })
        XCTAssertTrue(result.calls.contains { $0["route"] == .string("raw") && $0["body"] == reason })
        XCTAssertTrue(
            result.calls.contains {
                $0["route"] == .string("session") && $0["id"] == .string("per_deny")
                    && $0["session"] == .string("ses_1") && $0["body"] == .object(["response": .string("reject")])
            })
        XCTAssertTrue(routes(result, id: "per_wait").isEmpty, "answered in the terminal first")

        // No route took it: OpenCode still asks, and Wisp hears about it.
        XCTAssertEqual(routes(result, id: "per_fail"), ["public", "raw", "session"])
        let failed = try XCTUnwrap(result.sent.first { $0["hook_event_name"] == .string("permission.reply_failed") })
        XCTAssertEqual(failed["request_id"], .string("per_fail"))
        let event = try XCTUnwrap(AgentSource.opencode.adapter.parse(.object(failed), terminal: nil))
        XCTAssertEqual(event.kind, .notification)
        XCTAssertEqual(event.notificationType, OpenCodeHooks.replyFailed)
    }

    func testAnOlderClientUsesTheRouteDirectly() throws {
        let result = try run(tools: false, expected: Self.sessionEvents.count, v1Client: true)
        XCTAssertEqual(routes(result, id: "per_ok"), ["raw"])
        XCTAssertEqual(routes(result, id: "per_fail"), ["raw", "session"])
    }

    func testEveryPayloadParses() throws {
        let result = try run(tools: true, expected: Self.sessionEvents.count + 2)
        XCTAssertEqual(result.sent.count, Self.sessionEvents.count + 2)
        let adapter = AgentSource.opencode.adapter
        let kinds = result.sent.compactMap { adapter.parse(.object($0), terminal: nil)?.kind }
        XCTAssertEqual(kinds.count, result.sent.count)
        XCTAssertFalse(kinds.contains(.other))
        XCTAssertTrue(kinds.contains(.preToolUse))
        let write = try XCTUnwrap(result.sent.first { $0["hook_event_name"] == .string("tool.execute.before") })
        XCTAssertEqual(write["args"], .object(["filePath": .string("/Users/me/site/a.ts")]))
        XCTAssertFalse(result.log.contains("Secret content"))
        XCTAssertFalse(result.log.contains("Secret output"))
    }
}
