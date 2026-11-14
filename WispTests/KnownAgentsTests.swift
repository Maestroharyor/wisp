import XCTest

@testable import WispCore

final class KnownAgentsTests: XCTestCase {
    private func match(_ name: String, _ arguments: [String]) -> String? {
        KnownAgents.match(name: name, arguments: arguments)?.id
    }

    func testTableIsUniqueAndLinksHookAgents() {
        XCTAssertEqual(Set(KnownAgents.all.map(\.id)).count, KnownAgents.all.count)
        for agent in KnownAgents.all {
            XCTAssertFalse(agent.name.isEmpty)
            XCTAssertFalse(agent.symbol.isEmpty)
            XCTAssertFalse(agent.binaries.isEmpty && agent.packages.isEmpty && agent.modules.isEmpty)
            if let id = agent.adapterID { XCTAssertNotNil(AgentAdapters.adapter(id: id), id) }
        }
        for id in ["qwen", "qoder", "droid", "codebuddy", "kimi", "grok", "vibe"] {
            XCTAssertEqual(KnownAgents.all.first { $0.adapterID == id }?.adapterID, id)
        }
        for id in [
            "aider", "goose", "amp", "trae", "antigravity", "deepseek", "zcode", "mimo", "pi", "crush", "cline", "kiro",
        ] {
            XCTAssertNotNil(KnownAgents.all.first { $0.id == id }, id)
        }
        XCTAssertEqual(KnownAgents.monitorOnly.map(\.id).contains("aider"), true)
        XCTAssertFalse(KnownAgents.monitorOnly.contains { $0.adapterID != nil })
        XCTAssertFalse(
            KnownAgents.all.contains { ["claude", "codex", "gemini", "copilot", "cursor", "opencode"].contains($0.id) })
    }

    func testNativeBinaries() {
        XCTAssertEqual(match("goose", ["/opt/homebrew/bin/goose", "session"]), "goose")
        XCTAssertEqual(match("droid", ["droid"]), "droid")
        XCTAssertEqual(match("crush", ["/usr/local/bin/crush"]), "crush")
        XCTAssertEqual(match("traecli", ["traecli"]), "trae")
        XCTAssertEqual(match("kiro-cli", ["kiro-cli", "chat"]), "kiro")
        XCTAssertEqual(match("deepseek-tui", ["/Users/me/.cargo/bin/deepseek-tui"]), "deepseek")
        XCTAssertEqual(match("agy", ["agy"]), "antigravity")
        XCTAssertNil(match("zsh", ["-zsh"]))
        XCTAssertNil(match("vim", ["vim", "aider.py"]), "an editor opening a file of the same name isn't the agent")
    }

    func testGooseNeedsOneOfItsOwnSubcommands() {
        // `goose` is also the name of a database migration tool.
        XCTAssertEqual(match("goose", ["goose"]), "goose")
        XCTAssertEqual(match("goose", ["/Users/me/.local/bin/goose", "run", "-t", "fix it"]), "goose")
        XCTAssertEqual(match("goose", ["goose", "--debug", "session", "--resume"]), "goose")
        XCTAssertNil(match("goose", ["/Users/me/go/bin/goose", "postgres", "user=me dbname=app", "up"]))
        XCTAssertNil(match("goose", ["goose", "-dir", "db/migrations", "status"]))
        XCTAssertNil(match("goose", ["goose", "create", "add_users", "sql"]))
        // Agents without a subcommand list match on their name alone.
        XCTAssertEqual(match("crush", ["crush", "anything"]), "crush")
    }

    func testNodeLaunchers() {
        XCTAssertEqual(match("node", ["node", "/opt/homebrew/bin/qwen"]), "qwen")
        XCTAssertEqual(
            match("node", ["/usr/local/bin/node", "/usr/local/lib/node_modules/@sourcegraph/amp/dist/main.js"]), "amp")
        XCTAssertEqual(
            match(
                "node", ["node", "--no-warnings", "/Users/me/.npm-global/lib/node_modules/@mimo-ai/cli/bin/mimo.js"]),
            "mimo")
        XCTAssertEqual(match("node", ["node", "/Users/me/.local/bin/pi"]), "pi")
        XCTAssertEqual(match("bun", ["bun", "/Users/me/.bun/bin/codebuddy"]), "codebuddy")
        // Node apps may rename themselves through process.title, which rewrites argv[0].
        XCTAssertEqual(match("node", ["qwen"]), "qwen")
        XCTAssertNil(match("node", ["node", "/Users/me/site/server.js"]))
        XCTAssertNil(match("node", ["node", "/usr/local/lib/node_modules/@qwen-code-fork/other/cli.js"]))
    }

    func testPythonLaunchers() {
        XCTAssertEqual(
            match("Python", ["/opt/homebrew/Cellar/python@3.12/Python", "/Users/me/.local/bin/aider"]), "aider")
        XCTAssertEqual(match("python3.12", ["python3.12", "-m", "aider", "--model", "x"]), "aider")
        XCTAssertEqual(match("python3", ["python3", "/Users/me/.local/bin/vibe"]), "vibe")
        XCTAssertEqual(match("python3", ["python3", "-m", "kimi_cli"]), "kimi")
        XCTAssertNil(match("python3", ["python3", "-m", "http.server"]))
        XCTAssertNil(match("python3", ["python3", "-c", "import aider"]))
    }

    func testOnlyTheOutermostProcessOfAnAgentCounts() {
        let qwen = KnownAgents.all.first { $0.id == "qwen" }
        let goose = KnownAgents.all.first { $0.id == "goose" }
        let found = KnownAgents.outermost([
            .init(pid: 10, parent: 1, agent: qwen), .init(pid: 11, parent: 10, agent: qwen),
            .init(pid: 12, parent: 10, agent: goose), .init(pid: 20, parent: 2, agent: qwen),
        ])
        XCTAssertEqual(found.map(\.pid), [10, 12, 20])
    }

    func testProcessArgumentsParse() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(3).littleEndian) { bytes += $0 }
        bytes += Array("/opt/homebrew/bin/node".utf8) + [0, 0, 0, 0]
        for argument in ["node", "/opt/homebrew/bin/qwen", "--yolo"] { bytes += Array(argument.utf8) + [0] }
        bytes += Array("SECRET=x".utf8) + [0]
        XCTAssertEqual(ProcessArguments.parse(Data(bytes)), ["node", "/opt/homebrew/bin/qwen", "--yolo"])
        XCTAssertNil(ProcessArguments.parse(Data([1, 0])))
        XCTAssertEqual(ProcessArguments.parse(Data(bytes.prefix(30))), [])
    }

    func testAppBundleFromAnExecutable() {
        XCTAssertEqual(
            KnownAgents.appBundlePath(
                executable: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            "/System/Applications/Utilities/Terminal.app")
        XCTAssertEqual(
            KnownAgents.appBundlePath(
                executable:
                    "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
            ),
            "/Applications/Visual Studio Code.app")
        XCTAssertNil(KnownAgents.appBundlePath(executable: "/usr/bin/login"))
    }

    func testMonitoredSessionNamesItsFolder() throws {
        let aider = KnownAgents.all.first { $0.id == "aider" }
        let session = MonitoredSession(
            agent: try XCTUnwrap(aider), pid: 42, started: 100, cwd: "/Users/me/blog", tty: "/dev/ttys003",
            terminal: nil)
        XCTAssertEqual(session.project, "blog")
        XCTAssertEqual(session.id, "aider-42-100")
        let unknown = MonitoredSession(agent: session.agent, pid: 42, started: 100, cwd: "", tty: nil, terminal: nil)
        XCTAssertEqual(unknown.project, "Aider")
    }
}
