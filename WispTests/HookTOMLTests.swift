import XCTest

@testable import WispCore

/// Wisp's `[[hooks]]` tables in Kimi Code's config.toml and Mistral Vibe's hooks.toml.
final class HookTOMLTests: XCTestCase {
    private let kimi = AgentSource.kimi.adapter.hookFile
    private let vibe = AgentSource.vibe.adapter.hookFile
    private let helper = "/Applications/Wisp's.app/Contents/MacOS/wisp-agent"

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    private let userConfig = """
        default_model = "kimi-k2"

        [[hooks]]
        event = "Notification"
        matcher = "task\\\\.completed"
        command = "terminal-notifier -title Kimi -message 'Task done'"

        # Keep this comment
        [models.kimi]
        name = "k2"
        """

    func testKimiInstallAppendsTablesAndKeepsTheRest() throws {
        let command = HookInstaller.command(helper: helper, file: kimi)
        let data = try HookInstaller.install(into: Data(userConfig.utf8), command: command, file: kimi)
        let output = text(data)
        XCTAssertTrue(output.hasPrefix(userConfig), "the user's file stays as written")
        XCTAssertTrue(output.contains("[[hooks]]\nevent = \"SessionStart\"\n"))
        XCTAssertTrue(
            output.contains(#"command = "'/Applications/Wisp'\\''s.app/Contents/MacOS/wisp-agent' --source kimi""#))
        XCTAssertTrue(output.contains("timeout = 5\n"))
        XCTAssertFalse(output.contains("PreToolUse"), "tool hooks only with tool activity on")
        XCTAssertEqual(output.components(separatedBy: "[[hooks]]").count - 1, 1 + kimi.events.count)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: helper, file: kimi), .this)
        XCTAssertEqual(try HookInstaller.link(in: data, helper: "/Other/wisp-agent", file: kimi), .other)
        XCTAssertFalse(try HookInstaller.toolsInstalled(in: data, file: kimi))
        XCTAssertEqual(try HookInstaller.installedApprovalTimeout(in: data, file: kimi), nil)
    }

    func testKimiInstallIsIdempotentAndRemovesCleanly() throws {
        let command = HookInstaller.command(helper: helper, file: kimi)
        let once = try HookInstaller.install(into: Data(userConfig.utf8), command: command, file: kimi, tools: true)
        let twice = try HookInstaller.install(into: once, command: command, file: kimi, tools: true)
        XCTAssertEqual(once, twice)
        XCTAssertTrue(try HookInstaller.toolsInstalled(in: once, file: kimi))
        let removed = try HookInstaller.remove(from: once, file: kimi)
        XCTAssertEqual(text(removed), userConfig + "\n")
        XCTAssertEqual(try HookInstaller.link(in: removed, helper: helper, file: kimi), HookLink.none)
    }

    func testMissingEventsReadAsOutdated() throws {
        let command = HookInstaller.command(helper: helper, file: kimi)
        let old = """
            [[hooks]]
            event = "Stop"
            command = "\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
            timeout = 5
            """
        XCTAssertEqual(try HookInstaller.link(in: Data(old.utf8), helper: helper, file: kimi), .outdated)
    }

    func testAnInlineHooksArrayIsRefused() {
        let inline = #"hooks = [{ event = "Stop", command = "say hi" }]"#
        XCTAssertThrowsError(
            try HookInstaller.install(into: Data(inline.utf8), command: "'/A/wisp-agent' --source kimi", file: kimi))
    }

    func testTableHeadersInsideMultilineStringsAreText() throws {
        let config = """
            notes = \"\"\"
            [[hooks]]
            command = "wisp-agent"
            \"\"\"
            """
        XCTAssertTrue(try HookTOML.commands(in: Data(config.utf8)).isEmpty)
        let removed = try HookInstaller.remove(from: Data(config.utf8), file: kimi)
        XCTAssertEqual(text(removed), config + "\n")
    }

    func testVibeTablesHaveNamesAndMatches() throws {
        let command = HookInstaller.command(helper: helper, file: vibe)
        let data = try HookInstaller.install(into: Data(), command: command, file: vibe)
        let output = text(data)
        XCTAssertTrue(output.hasPrefix("[[hooks]]\nname = \"wisp-pre-tool\"\ntype = \"pre_tool\"\nmatch = \"*\"\n"))
        XCTAssertTrue(output.contains("name = \"wisp-post-agent\"\ntype = \"post_agent\""))
        XCTAssertTrue(output.contains("timeout = 5.0\n"))
        XCTAssertEqual(try HookInstaller.link(in: data, helper: helper, file: vibe), .this)
        XCTAssertEqual(text(try HookInstaller.remove(from: data, file: vibe)), "")
    }

    func testStringParsing() {
        XCTAssertEqual(HookTOML.value(of: #"command = "a \"b\" \\ c" # note"#), #"a "b" \ c"#)
        XCTAssertEqual(HookTOML.value(of: "command = 'literal \\n'"), "literal \\n")
        XCTAssertEqual(HookTOML.value(of: #"command = "tab\there\u0041""#), "tab\thereA")
        XCTAssertNil(HookTOML.value(of: "timeout = 5"))
        XCTAssertEqual(HookTOML.quoted("it's \"x\"\\\n"), #""it's \"x\"\\\n""#)
    }

    /// The installer only ever sees bytes; this checks the whole round trip through a file in a
    /// temporary folder, never the real home.
    func testRoundTripThroughATemporaryFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = kimi.url(home: folder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(userConfig.utf8).write(to: url)
        let command = HookInstaller.command(helper: helper, file: kimi)
        try HookInstaller.install(into: Data(contentsOf: url), command: command, file: kimi).write(to: url)
        XCTAssertEqual(try HookInstaller.link(in: Data(contentsOf: url), helper: helper, file: kimi), .this)
        try HookInstaller.remove(from: Data(contentsOf: url), file: kimi).write(to: url)
        XCTAssertEqual(text(try Data(contentsOf: url)), userConfig + "\n")
    }
}
