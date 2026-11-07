import XCTest

@testable import WispCore

final class AgentAdapterTests: XCTestCase {
    func testRegistryListsEachAgentOnceByItsWireID() {
        XCTAssertEqual(AgentAdapters.all.map(\.source), [.claude, .codex, .gemini, .cursor])
        XCTAssertEqual(AgentAdapters.adapter(id: "codex")?.displayName, "Codex")
        XCTAssertEqual(AgentAdapters.adapter(id: "gemini")?.displayName, "Gemini CLI")
        XCTAssertNil(AgentAdapters.adapter(id: "aider"))
        XCTAssertEqual(Set(AgentAdapters.all.map(\.source.rawValue)).count, AgentAdapters.all.count)
    }

    func testSourcesAreStringIDsAndUnknownOnesDontExist() throws {
        XCTAssertEqual(AgentSource(rawValue: "claude"), .claude)
        XCTAssertEqual(AgentSource(rawValue: "codex"), .codex)
        XCTAssertEqual(AgentSource(rawValue: "gemini"), .gemini)
        XCTAssertNil(AgentSource(rawValue: "aider"))
        let encoded = try JSONEncoder().encode([AgentSource.codex])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"["codex"]"#)
        XCTAssertEqual(try JSONDecoder().decode([AgentSource].self, from: encoded), [.codex])
        XCTAssertThrowsError(try JSONDecoder().decode([AgentSource].self, from: Data(#"["aider"]"#.utf8)))
    }

    func testNamesSymbolsAndHookFiles() {
        XCTAssertEqual(AgentSource.claude.displayName, "Claude Code")
        XCTAssertEqual(AgentSource.claude.adapter.symbol, "sparkle")
        XCTAssertEqual(AgentSource.codex.adapter.symbol, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(AgentSource.claude.adapter.hookFile.displayPath, "~/.claude/settings.json")
        XCTAssertEqual(AgentSource.codex.adapter.hookFile.displayPath, "~/.codex/hooks.json")
        XCTAssertEqual(AgentSource.claude.adapter.hookFile.format, .claudeSettings)
        XCTAssertEqual(AgentSource.codex.adapter.hookFile.format, .codexHooks)
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(AgentSource.codex.adapter.hookFile.url(home: home).path, "/Users/me/.codex/hooks.json")
    }

    func testCapabilities() {
        let claude = AgentSource.claude.adapter.capabilities
        let codex = AgentSource.codex.adapter.capabilities
        XCTAssertTrue(claude.isSuperset(of: [.approve, .answerQuestions, .statusLine, .limits, .compaction, .rules]))
        XCTAssertTrue(codex.isSuperset(of: [.approve, .limits, .compaction, .toolActivity]))
        XCTAssertFalse(codex.contains(.answerQuestions), "Codex fails closed on updatedInput")
        XCTAssertFalse(codex.contains(.statusLine))
        XCTAssertFalse(codex.contains(.rules))
        XCTAssertTrue(AgentSource.claude.adapter.hookFile.statusLine)
        XCTAssertFalse(AgentSource.codex.adapter.hookFile.statusLine)
    }

    func testCodexToolHooksRunInTheBackground() {
        let codex = AgentSource.codex
        XCTAssertEqual(codex.toolHookEvents, ["PreToolUse", "PostToolUse", "SubagentStop"])
        XCTAssertEqual(codex.backgroundHookEvents, Set(codex.toolHookEvents))
        XCTAssertFalse(codex.hookEvents.contains("Notification"))
    }

    func testHelperArgumentsTagEveryAgentButTheDefault() {
        XCTAssertEqual(AgentSource.claude.adapter.hookFile.helperArguments, "")
        XCTAssertEqual(AgentSource.codex.adapter.hookFile.helperArguments, " --source codex")
    }

    func testToolKindFollowsTheSource() {
        let pre = Data(#"{"hook_event_name":"PreToolUse"}"#.utf8)
        XCTAssertEqual(AgentProtocol.kind(forHook: pre, source: .codex), .tool)
        XCTAssertEqual(AgentProtocol.kind(forHook: Data(#"{"hook_event_name":"Stop"}"#.utf8), source: .codex), .hook)
    }

    func testAnUnknownSourceIsUnsupported() throws {
        XCTAssertEqual(
            try AgentProtocol.decode(
                Data(#"{"v":1,"kind":"hook","source":"aider","payload":{"hook_event_name":"Stop"}}"#.utf8)),
            .unsupported("source aider"))
        XCTAssertEqual(
            try AgentProtocol.decode(Data(#"{"session_id":"s","hook_event_name":"Stop","wisp_source":"aider"}"#.utf8)),
            .unsupported("source aider"))
    }

    func testAMissingSourceIsClaude() throws {
        guard case .hook(let event) = try AgentProtocol.decode(Data(#"{"v":1,"kind":"hook","payload":{}}"#.utf8))
        else { return XCTFail("not a hook") }
        XCTAssertEqual(event.source, .claude)
    }

    func testANonObjectPayloadIsUnsupported() throws {
        XCTAssertEqual(
            try AgentProtocol.decode(Data(#"{"v":1,"kind":"hook","source":"codex","payload":[1]}"#.utf8)),
            .unsupported("hook payload"))
    }
}

final class ClaudeAdapterTests: XCTestCase {
    private let adapter = AgentSource.claude.adapter

    func testParsesAPermissionRequest() throws {
        let json = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(
                #"{"session_id":"s1","cwd":"/Users/me/app","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"},"transcript_path":"/t/s1.jsonl"}"#
                    .utf8))
        let event = try XCTUnwrap(adapter.parse(json, terminal: "com.apple.Terminal"))
        XCTAssertEqual(event.kind, .permissionRequest)
        XCTAssertEqual(event.source, .claude)
        XCTAssertEqual(event.summary, "npm test")
        XCTAssertEqual(event.project, "app")
        XCTAssertEqual(event.prompt, .tool)
    }

    func testPlansAndQuestionsNeedTheUser() {
        XCTAssertEqual(adapter.prompt(tool: "ExitPlanMode"), .plan)
        XCTAssertEqual(adapter.prompt(tool: "AskUserQuestion"), .question)
    }

    /// Replies compared as parsed JSON: the encoder doesn't fix key order, so two encodings of
    /// the same reply can differ as text.
    private func json(_ text: String?) -> JSONValue? {
        text.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    }

    func testRepliesMatchPermissionReply() {
        let plan: JSONValue = .object(["plan": .string("# Fix")])
        XCTAssertNotNil(json(adapter.reply(.decide(.plan, allow: true, input: plan))))
        XCTAssertEqual(
            json(adapter.reply(.decide(.plan, allow: true, input: plan))),
            json(PermissionReply.answer(.plan, allow: true, input: plan)))
        XCTAssertEqual(
            json(adapter.reply(.decide(.tool, allow: true, input: nil))), json(PermissionReply.json(allow: true)))
        XCTAssertEqual(
            json(adapter.reply(.deny(.tool, reason: "no"))),
            json(PermissionReply.json(allow: false, denial: "Denied from the Wisp notch: no")))
        XCTAssertNil(adapter.reply(.decide(.question, allow: true, input: nil)))
        let questions: JSONValue = .object(["questions": .array([])])
        XCTAssertNotNil(json(adapter.reply(.answer(input: questions, answers: ["Q": "A"]))))
        XCTAssertEqual(
            json(adapter.reply(.answer(input: questions, answers: ["Q": "A"]))),
            json(QuestionReply.json(input: questions, answers: ["Q": "A"])))
    }

    func testParseNeedsAnObject() {
        XCTAssertNil(adapter.parse(.array([]), terminal: nil))
    }
}

final class CodexAdapterTests: XCTestCase {
    private let adapter = AgentSource.codex.adapter

    private func event(_ text: String) throws -> AgentEvent {
        try XCTUnwrap(adapter.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), terminal: nil))
    }

    // Shape from Codex's hooks docs (PermissionRequest), with made-up values.
    func testParsesAPermissionRequest() throws {
        let event = try event(
            #"{"session_id":"thr_1","turn_id":"t1","transcript_path":null,"cwd":"/work/api","hook_event_name":"PermissionRequest","model":"gpt-5.3-codex","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Clean the build folder"}}"#
        )
        XCTAssertEqual(event.kind, .permissionRequest)
        XCTAssertEqual(event.source, .codex)
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.summary, "rm -rf build")
        XCTAssertEqual(event.project, "api")
        XCTAssertNil(event.transcriptPath)
        XCTAssertEqual(event.prompt, .tool)
    }

    func testAPatchIsShownByItsFirstFile() throws {
        let event = try event(
            #"{"session_id":"s","cwd":"/w","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_use_id":"call_1","tool_input":{"command":"*** Begin Patch\n*** Update File: src/main.rs\n@@\n-old\n+new\n*** Add File: src/new.rs\n+x\n*** End Patch"}}"#
        )
        XCTAssertEqual(event.summary, "src/main.rs")
        XCTAssertEqual(event.toolInput.filePath, "src/main.rs")
        XCTAssertNil(event.toolInput.command, "the patch body never becomes a label")
        XCTAssertEqual(event.toolUseID, "call_1")
        XCTAssertEqual(
            ToolLabel.describe(tool: event.toolName, input: event.toolInput, hidden: false).label, "Editing main.rs")
    }

    func testPatchPaths() {
        XCTAssertEqual(CodexPatch.firstPath("*** Begin Patch\n*** Delete File: a.txt\n*** End Patch"), "a.txt")
        XCTAssertEqual(CodexPatch.firstPath("*** Begin Patch\n*** Add File:  b/c.md \n+x"), "b/c.md")
        XCTAssertNil(CodexPatch.firstPath("echo hi"))
    }

    func testToolNamesNeverAskForPlansOrQuestions() {
        XCTAssertEqual(adapter.prompt(tool: "ExitPlanMode"), .tool)
        XCTAssertEqual(adapter.prompt(tool: "AskUserQuestion"), .tool)
    }

    // Codex documents allow and deny with `hookSpecificOutput.decision`; `updatedInput` fails closed.
    func testRepliesNeverSendUpdatedInput() throws {
        let allow = try XCTUnwrap(adapter.reply(.decide(.plan, allow: true, input: .object(["plan": .string("x")]))))
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(allow.utf8))
        XCTAssertEqual(json["hookSpecificOutput"]?["hookEventName"], .string("PermissionRequest"))
        XCTAssertEqual(json["hookSpecificOutput"]?["decision"]?["behavior"], .string("allow"))
        XCTAssertNil(json["hookSpecificOutput"]?["decision"]?["updatedInput"])
        let deny = try XCTUnwrap(adapter.reply(.deny(.tool, reason: "")))
        let denied = try JSONDecoder().decode(JSONValue.self, from: Data(deny.utf8))
        XCTAssertEqual(denied["hookSpecificOutput"]?["decision"]?["behavior"], .string("deny"))
        XCTAssertEqual(denied["hookSpecificOutput"]?["decision"]?["message"], .string(PermissionReply.defaultDenial))
        XCTAssertNil(adapter.reply(.answer(input: .object([:]), answers: ["Q": "A"])))
    }

    func testCodexInstallsToolHooksInTheBackground() throws {
        let out = try JSONDecoder().decode(
            JSONValue.self,
            from: HookInstaller.install(
                into: Data("{}".utf8), command: "'/x/wisp-agent' --source codex", source: .codex, tools: true))
        XCTAssertEqual(out["hooks"]?["PreToolUse"]?[0]?["hooks"]?[0]?["async"], .bool(true))
        XCTAssertEqual(out["hooks"]?["SubagentStop"]?[0]?["hooks"]?[0]?["async"], .bool(true))
        XCTAssertNil(out["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["async"])
        let data = try HookInstaller.install(
            into: Data("{}".utf8), command: "'/x/wisp-agent' --source codex", source: .codex, tools: true)
        XCTAssertTrue(try HookInstaller.toolsInstalled(in: data, file: AgentSource.codex.adapter.hookFile))
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/x/wisp-agent", source: .codex), .this)
    }
}

final class HookFileInstallTests: XCTestCase {
    /// Settings live in a temporary folder; nothing touches the real home.
    func testInstallsIntoTheFileAtItsPathUnderAGivenHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for adapter in AgentAdapters.all {
            let url = adapter.hookFile.url(home: home)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let command = HookInstaller.command(helper: "/A/wisp-agent", file: adapter.hookFile)
            try HookInstaller.install(into: Data(), command: command, file: adapter.hookFile).write(to: url)
            XCTAssertEqual(
                try HookInstaller.link(in: Data(contentsOf: url), helper: "/A/wisp-agent", file: adapter.hookFile),
                .this)
        }
    }
}
