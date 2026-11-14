import XCTest

@testable import WispCore

final class RuleSuggestionTests: XCTestCase {
    private func bash(_ command: String) -> [[String]] {
        RuleSuggestion.choices(tool: "Bash", input: .object(["command": .string(command)]), cwd: "/p/app")
    }

    // MARK: Choices

    func testOffersTheExactCommandThenShorterPrefixes() {
        XCTAssertEqual(
            bash("git log --oneline -5"),
            [["Bash(git log --oneline -5)"], ["Bash(git log --oneline *)"], ["Bash(git log *)"]])
        XCTAssertEqual(bash("npm test"), [["Bash(npm test)"], ["Bash(npm test *)"]])
    }

    func testPackageScriptsKeepTheScriptName() {
        XCTAssertEqual(
            bash("npm run build --watch"), [["Bash(npm run build --watch)"], ["Bash(npm run build *)"]])
    }

    func testNeverWidensToTheProgramAlone() {
        XCTAssertFalse(bash("git status --short").flatMap { $0 }.contains("Bash(git *)"))
    }

    func testDestructiveAndRunnerCommandsStayExact() {
        XCTAssertEqual(bash("git push origin main"), [["Bash(git push origin main)"]])
        XCTAssertEqual(bash("cargo run --release"), [["Bash(cargo run --release)"]])
        XCTAssertEqual(bash("rm -rf build"), [["Bash(rm -rf build)"]])
    }

    func testRefusesCompoundCommandsAndSubstitutions() {
        XCTAssertEqual(bash("git add . && git commit -m wip"), [])
        XCTAssertEqual(bash("ls | wc -l"), [])
        XCTAssertEqual(bash("echo $(whoami)"), [])
        XCTAssertEqual(bash("echo `date`"), [])
    }

    func testQuotedWordsEndThePrefixes() {
        XCTAssertEqual(
            bash("git commit -m \"fix it\""),
            [
                ["Bash(git commit -m \"fix it\")"], ["Bash(git commit -m *)"],
                ["Bash(git commit *)"],
            ])
    }

    func testCapsTheNumberOfChoices() {
        XCTAssertEqual(bash("git log a b c d e f").count, RuleSuggestion.maximumChoices)
    }

    func testOtherToolsOfferTheExistingSuggestion() {
        let choices = RuleSuggestion.choices(
            tool: "Edit", input: .object(["file_path": .string("/p/app/src/a.swift")]), cwd: "/p/app")
        XCTAssertEqual(choices, [["Edit(src/**)"]])
        XCTAssertEqual(RuleSuggestion.choices(tool: "Task", input: nil, cwd: "/p/app"), [])
    }

    // MARK: Matching

    func testPrefixRuleMatchesWordsNotLetters() {
        XCTAssertTrue(PermissionRule.matches("Bash(git log *)", tool: "Bash", summary: "git log --oneline"))
        XCTAssertTrue(PermissionRule.matches("Bash(git log *)", tool: "Bash", summary: "git log"))
        XCTAssertFalse(PermissionRule.matches("Bash(git log *)", tool: "Bash", summary: "git logs"))
        XCTAssertTrue(PermissionRule.matches("Bash(git log:*)", tool: "Bash", summary: "git log -p"))
        XCTAssertFalse(PermissionRule.matches("Bash(git log *)", tool: "Edit", summary: "git log"))
    }

    func testExactRuleMatchesOnlyThatCommand() {
        XCTAssertTrue(PermissionRule.matches("Bash(npm test)", tool: "Bash", summary: "npm test"))
        XCTAssertFalse(PermissionRule.matches("Bash(npm test)", tool: "Bash", summary: "npm test --watch"))
    }

    func testEveryPartOfACompoundCommandMustMatch() {
        XCTAssertFalse(PermissionRule.matches("Bash(git log *)", tool: "Bash", summary: "git log && rm -rf x"))
        XCTAssertTrue(PermissionRule.matches("Bash(git log *)", tool: "Bash", summary: "cd app && git log"))
    }

    func testFileRules() {
        XCTAssertTrue(PermissionRule.matches("Edit(src/**)", tool: "Write", summary: "/p/app/src/x/a.swift"))
        XCTAssertFalse(PermissionRule.matches("Edit(src/**)", tool: "Write", summary: "/p/app/tests/a.swift"))
        XCTAssertTrue(PermissionRule.matches("Edit(//p/app/README.md)", tool: "Edit", summary: "/p/app/README.md"))
        XCTAssertTrue(PermissionRule.matches("Read(//p/app/docs/**)", tool: "Read", summary: "/p/app/docs/a.md"))
        XCTAssertFalse(PermissionRule.matches("Read(src/**)", tool: "Edit", summary: "/p/app/src/a.swift"))
    }

    func testDomainAndMCPRules() {
        XCTAssertTrue(
            PermissionRule.matches(
                "WebFetch(domain:docs.swift.org)", tool: "WebFetch", summary: "https://docs.swift.org/a"))
        XCTAssertFalse(
            PermissionRule.matches("WebFetch(domain:docs.swift.org)", tool: "WebFetch", summary: "https://swift.org"))
        XCTAssertTrue(PermissionRule.matches("mcp__gh__list", tool: "mcp__gh__list", summary: ""))
        XCTAssertFalse(PermissionRule.matches("mcp__gh__list", tool: "mcp__gh__view", summary: ""))
    }

    func testCountsMatchesAmongTheLastToolRequests() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var log = ApprovalLog()
        for (index, command) in ["git log", "git log -p", "git status", "npm test"].enumerated() {
            log.add(
                ApprovalRecord(
                    sessionID: "s", project: "app", source: .claude, tool: "Bash", summary: command, outcome: .allowed,
                    date: now.addingTimeInterval(Double(index))), now: now)
        }
        // Hidden while recorded: no summary, so it can't be matched.
        log.add(
            ApprovalRecord(
                sessionID: "s", project: "app", source: .claude, tool: "Bash", summary: nil, outcome: .allowed,
                date: now), now: now)
        let recent = log.recentToolRequests(RuleSuggestion.window)
        XCTAssertEqual(RuleSuggestion.matchCount(["Bash(git log *)"], in: recent), 2)
        XCTAssertEqual(RuleSuggestion.matchCount(["Bash(git status)"], in: recent), 1)
        XCTAssertEqual(RuleSuggestion.matchText(count: 2, of: recent.count), "Matches 2 of your last 5 requests")
        XCTAssertEqual(RuleSuggestion.matchText(count: 1, of: 1), "Matches 1 of your last request")
        XCTAssertNil(RuleSuggestion.matchText(count: 0, of: 0))
    }
}
