import XCTest

@testable import WispCore

final class AgentSourceTests: XCTestCase {
    func testHelperTagsSourceTerminalAndFolder() throws {
        let event = try AgentEvent.decode(
            Data(
                #"{"session_id":"c1","cwd":"/Users/me/api","hook_event_name":"UserPromptSubmit","transcript_path":"/t/c1.jsonl","wisp_source":"codex","wisp_terminal":"com.mitchellh.ghostty"}"#
                    .utf8))
        XCTAssertEqual(event.source, .codex)
        XCTAssertEqual(event.terminal, "com.mitchellh.ghostty")
        XCTAssertEqual(event.cwd, "/Users/me/api")
        XCTAssertEqual(event.transcriptPath, "/t/c1.jsonl")
    }

    func testDefaultsToClaudeWithNoTerminal() throws {
        let event = try AgentEvent.decode(Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8))
        XCTAssertEqual(event.source, .claude)
        XCTAssertNil(event.terminal)
        XCTAssertNil(event.transcriptPath)
        XCTAssertEqual(event.project, "Claude")
    }

    func testCodexSessionsWithoutAFolderAreNamedCodex() throws {
        let event = try AgentEvent.decode(
            Data(#"{"session_id":"s","hook_event_name":"Stop","wisp_source":"codex"}"#.utf8))
        XCTAssertEqual(event.project, "Codex")
    }

    func testTerminalFromEnvironment() {
        XCTAssertEqual(
            AgentTerminal.bundleID(cfBundleIdentifier: "com.googlecode.iterm2", termProgram: nil),
            "com.googlecode.iterm2")
        XCTAssertEqual(
            AgentTerminal.bundleID(cfBundleIdentifier: nil, termProgram: "Apple_Terminal"), "com.apple.Terminal")
        XCTAssertEqual(AgentTerminal.bundleID(cfBundleIdentifier: nil, termProgram: "ghostty"), "com.mitchellh.ghostty")
        XCTAssertEqual(AgentTerminal.bundleID(cfBundleIdentifier: nil, termProgram: "vscode"), "com.microsoft.VSCode")
        XCTAssertNil(AgentTerminal.bundleID(cfBundleIdentifier: nil, termProgram: "tmux"))
        XCTAssertNil(AgentTerminal.bundleID(cfBundleIdentifier: "", termProgram: nil))
    }

    func testTaggingAddsFieldsAndLeavesOtherInputAlone() throws {
        let tagged = AgentTerminal.tag(
            Data(#"{"session_id":"s","cwd":"/a"}"#.utf8), source: .codex, terminal: "com.apple.Terminal")
        let json = try JSONDecoder().decode(JSONValue.self, from: tagged)
        XCTAssertEqual(json["wisp_source"], .string("codex"))
        XCTAssertEqual(json["wisp_terminal"], .string("com.apple.Terminal"))
        XCTAssertEqual(json["session_id"], .string("s"))
        let garbage = Data("not json".utf8)
        XCTAssertEqual(AgentTerminal.tag(garbage, source: .claude, terminal: nil), garbage)
    }

    func testSessionsKeepTerminalAndSource() throws {
        var sessions = AgentSessions()
        let start = Date(timeIntervalSince1970: 0)
        sessions.apply(
            try AgentEvent.decode(
                Data(
                    #"{"session_id":"s","cwd":"/p/app","hook_event_name":"SessionStart","wisp_source":"codex","wisp_terminal":"com.apple.Terminal","transcript_path":"/t"}"#
                        .utf8)), at: start)
        // A later event without the terminal must not erase it.
        sessions.apply(
            try AgentEvent.decode(Data(#"{"session_id":"s","cwd":"/p/app","hook_event_name":"Stop"}"#.utf8)), at: start)
        let session = try XCTUnwrap(sessions.list.first)
        XCTAssertEqual(session.source, .codex)
        XCTAssertEqual(session.terminal, "com.apple.Terminal")
        XCTAssertEqual(session.cwd, "/p/app")
        XCTAssertEqual(session.transcriptPath, "/t")
    }

    func testSessionsRecordUsage() throws {
        var sessions = AgentSessions()
        sessions.apply(
            try AgentEvent.decode(Data(#"{"session_id":"s","hook_event_name":"SessionStart"}"#.utf8)),
            at: Date(timeIntervalSince1970: 0))
        sessions.setUsage(TokenUsage(input: 10, output: 5), cost: 0.5, session: "s")
        XCTAssertEqual(sessions.list.first?.usage, TokenUsage(input: 10, output: 5))
        XCTAssertEqual(sessions.list.first?.cost, 0.5)
    }
}

final class TranscriptUsageTests: XCTestCase {
    private func line(_ id: String, model: String, input: Int, output: Int, write: Int = 0, read: Int = 0) -> String {
        #"{"type":"assistant","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(write),"cache_read_input_tokens":\#(read)}}}"#
    }

    func testSumsClaudeUsageCountingEachMessageOnce() {
        var usage = TranscriptUsage()
        usage.add(lines: [
            #"{"type":"user","message":{"content":"hi"}}"#,
            line("m1", model: "claude-opus-5-5", input: 100, output: 20, write: 1_000, read: 0),
            // The same message logged again for its next content block.
            line("m1", model: "claude-opus-5-5", input: 100, output: 20, write: 1_000, read: 0),
            line("m2", model: "claude-opus-5-5", input: 10, output: 50, write: 0, read: 1_000),
            "not json",
        ])
        XCTAssertEqual(usage.total, TokenUsage(input: 110, output: 70, cacheWrite: 1_000, cacheRead: 1_000))
        XCTAssertEqual(usage.total.all, 2_180)
    }

    func testReadsCodexTokenCountsAsARunningTotal() {
        var usage = TranscriptUsage()
        usage.add(lines: [
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":200,"output_tokens":40}}}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":300,"output_tokens":90}}}}"#,
        ])
        XCTAssertEqual(usage.total, TokenUsage(input: 600, output: 90, cacheRead: 300))
        XCTAssertNil(usage.cost(), "Codex models have no price in the table")
    }

    func testCostUsesThePriceOfEachModel() throws {
        var usage = TranscriptUsage()
        usage.add(lines: [
            line("a", model: "claude-opus-5-5", input: 1_000_000, output: 1_000_000),
            line("b", model: "claude-sonnet-5-5", input: 0, output: 0, write: 1_000_000, read: 1_000_000),
        ])
        // Opus 5.5: $4 in + $20 out. Sonnet 5.5: 1.25 × $2 write + $0.20 read.
        XCTAssertEqual(try XCTUnwrap(usage.cost()), 4 + 20 + 2.5 + 0.2, accuracy: 1e-9)
    }

    func testCostIsUnknownWhenAnyModelIsUnpriced() {
        var usage = TranscriptUsage()
        usage.add(lines: [line("a", model: "claude-opus-4-5", input: 10, output: 10)])
        XCTAssertNil(usage.cost())
    }

    func testPricingMatchesIDsWithSuffixes() {
        XCTAssertEqual(ModelPricing.price(for: "claude-opus-5-5[1m]")?.input, 4)
        XCTAssertEqual(ModelPricing.price(for: "claude-opus-5")?.input, 5)
        XCTAssertEqual(ModelPricing.price(for: "claude-sonnet-4-6")?.output, 15)
        XCTAssertNil(ModelPricing.price(for: "gpt-5"))
    }

    func testSummaryText() {
        XCTAssertEqual(TokenUsage(input: 182_000, output: 400).summary(cost: 0.41), "182k tokens · ~$0.41")
        XCTAssertEqual(TokenUsage(input: 900, output: 0).summary(cost: nil), "900 tokens")
        XCTAssertEqual(TokenUsage(input: 2_400_000).summary(cost: 12.5), "2.4M tokens · ~$12.50")
        XCTAssertEqual(TokenUsage(input: 999_499).summary(cost: nil), "999k tokens")
        XCTAssertEqual(TokenUsage(input: 999_700).summary(cost: nil), "1.0M tokens")
    }
}

final class ProjectColorTests: XCTestCase {
    func testSameProjectSameHue() {
        XCTAssertEqual(ProjectColor.hue(for: "wisp"), ProjectColor.hue(for: "wisp"))
    }

    func testHuesComeFromThePaletteAndSpread() {
        let names = ["wisp", "api", "web", "infra", "docs", "mobile", "cli", "site", "blog", "shop"]
        let hues = names.map(ProjectColor.hue(for:))
        XCTAssertTrue(hues.allSatisfy(ProjectColor.palette.contains))
        XCTAssertGreaterThan(Set(hues).count, 4)
    }

    func testPaletteAvoidsStatusColours() {
        // Amber (waiting) sits near 0.11 and green (done) near 0.36.
        XCTAssertFalse(ProjectColor.palette.contains { abs($0 - 0.11) < 0.04 || abs($0 - 0.36) < 0.05 })
    }
}

final class HookInstallerCodexTests: XCTestCase {
    func testCodexInstallsItsEventsWithTheSourceFlag() throws {
        let out = try JSONDecoder().decode(
            JSONValue.self,
            from: HookInstaller.install(
                into: Data("{}".utf8), command: "'/x/wisp-agent' --source codex", source: .codex))
        XCTAssertNil(out["hooks"]?["Notification"])
        XCTAssertEqual(out["hooks"]?["PermissionRequest"]?[0]?["hooks"]?[0]?["timeout"], .number(120))
        XCTAssertEqual(
            out["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["command"], .string("'/x/wisp-agent' --source codex"))
        XCTAssertEqual(AgentSource.codex.hookEvents.count, 5)
    }
}
