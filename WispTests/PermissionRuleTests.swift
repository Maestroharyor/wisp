import XCTest

@testable import WispCore

final class PermissionRuleTests: XCTestCase {
    private let cwd = "/Users/me/app"

    private func bash(_ command: String) -> [String] {
        PermissionRule.suggest(tool: "Bash", input: .object(["command": .string(command)]), cwd: cwd)
    }

    private func file(_ tool: String, _ path: String, key: String = "file_path") -> [String] {
        PermissionRule.suggest(tool: tool, input: .object([key: .string(path)]), cwd: cwd)
    }

    // MARK: Bash

    func testACommandWithASubcommandBecomesAPrefixRule() {
        XCTAssertEqual(bash("git commit -m 'Fix the build'"), ["Bash(git commit *)"])
        XCTAssertEqual(bash("make test"), ["Bash(make test *)"])
        XCTAssertEqual(bash("cargo test --workspace"), ["Bash(cargo test *)"])
    }

    func testAPackageScriptKeepsItsName() {
        XCTAssertEqual(bash("npm run test"), ["Bash(npm run test *)"])
        XCTAssertEqual(bash("pnpm run build:prod --filter web"), ["Bash(pnpm run build:prod *)"])
        XCTAssertEqual(bash("npm test"), ["Bash(npm test *)"])
    }

    func testABareCommandIsMatchedExactly() {
        XCTAssertEqual(bash("ls"), ["Bash(ls)"])
        XCTAssertEqual(bash("  pwd  "), ["Bash(pwd)"])
    }

    func testFlagsFilesAndPathsFallBackToTheExactCommand() {
        XCTAssertEqual(bash("ls -la"), ["Bash(ls -la)"])
        XCTAssertEqual(bash("python3 manage.py migrate"), ["Bash(python3 manage.py migrate)"])
        XCTAssertEqual(bash("./scripts/build.sh release"), ["Bash(./scripts/build.sh release)"])
        XCTAssertEqual(bash("swift build"), ["Bash(swift build *)"])
    }

    func testRiskyProgramsAndRunnersAreNeverWidened() {
        XCTAssertEqual(bash("rm -rf build"), ["Bash(rm -rf build)"])
        XCTAssertEqual(bash("rm build"), ["Bash(rm build)"])
        XCTAssertEqual(bash("sudo make install"), ["Bash(sudo make install)"])
        XCTAssertEqual(bash("npx prettier --check src"), ["Bash(npx prettier --check src)"])
        XCTAssertEqual(bash("npm exec tsc"), ["Bash(npm exec tsc)"])
        XCTAssertEqual(bash("cargo run --release"), ["Bash(cargo run --release)"])
        XCTAssertEqual(bash("bash -c 'echo hi'"), ["Bash(bash -c 'echo hi')"])
        XCTAssertEqual(bash("find build -type f -delete"), ["Bash(find build -type f -delete)"])
    }

    func testDestructiveSubcommandsKeepTheExactCommand() {
        XCTAssertEqual(bash("git push --force origin main"), ["Bash(git push --force origin main)"])
        XCTAssertEqual(bash("git reset --hard HEAD"), ["Bash(git reset --hard HEAD)"])
        XCTAssertEqual(bash("git clean -fd"), ["Bash(git clean -fd)"])
        XCTAssertEqual(bash("npm publish"), ["Bash(npm publish)"])
        XCTAssertEqual(bash("kubectl-like delete pod"), ["Bash(kubectl-like delete pod)"])
        XCTAssertEqual(bash("git status"), ["Bash(git status *)"])
    }

    // MARK: Scope

    func testEverywhereAnchorsProjectRelativeFileRules() {
        XCTAssertEqual(
            PermissionRule.anchored(["Edit(src/views/**)", "Read(docs/**)"], cwd: cwd),
            ["Edit(//Users/me/app/src/views/**)", "Read(//Users/me/app/docs/**)"])
    }

    func testAnchoringLeavesOtherRulesAlone() {
        let rules = [
            "Edit(//etc/hosts)", "Read(~/notes/**)", "Edit(/src/**)", "Bash(npm test *)", "WebFetch(domain:a.b)",
        ]
        XCTAssertEqual(PermissionRule.anchored(rules, cwd: cwd), rules)
    }

    func testAnchoringEscapesTheProjectFolder() {
        XCTAssertEqual(
            PermissionRule.anchored(["Edit(src/**)"], cwd: "/Users/me/[app]"), ["Edit(//Users/me/\\[app\\]/src/**)"])
    }

    func testAnchoringNeedsAnAbsoluteFolder() {
        XCTAssertEqual(PermissionRule.anchored(["Edit(src/**)"], cwd: ""), ["Edit(src/**)"])
    }

    func testAnEnvironmentPrefixKeepsTheExactCommand() {
        XCTAssertEqual(bash("FOO=1 npm test"), ["Bash(FOO=1 npm test)"])
    }

    func testArgumentFreeWrappersAreDropped() {
        XCTAssertEqual(bash("time npm test"), ["Bash(npm test *)"])
        XCTAssertEqual(bash("nohup make build"), ["Bash(make build *)"])
        XCTAssertEqual(bash("timeout 30 npm test"), ["Bash(timeout 30 npm test)"])
    }

    func testRedirectsKeepTheExactCommand() {
        XCTAssertEqual(bash("git log > log.txt"), ["Bash(git log > log.txt)"])
    }

    func testQuotedSubcommandWordsAreNotWidened() {
        XCTAssertEqual(bash("git 'push' origin"), ["Bash(git 'push' origin)"])
    }

    func testCompoundCommandsGetARulePerPart() {
        XCTAssertEqual(bash("npm install && npm test"), ["Bash(npm install *)", "Bash(npm test *)"])
        XCTAssertEqual(bash("git status | grep modified"), ["Bash(git status *)", "Bash(grep modified *)"])
        XCTAssertEqual(bash("make build; make test"), ["Bash(make build *)", "Bash(make test *)"])
    }

    func testCdInsideACompoundIsLeftOut() {
        XCTAssertEqual(bash("cd packages/api && npm test"), ["Bash(npm test *)"])
        XCTAssertEqual(bash("cd packages/api"), [])
    }

    func testRepeatedPartsAreListedOnce() {
        XCTAssertEqual(bash("make test && make test"), ["Bash(make test *)"])
    }

    func testSeparatorsInsideQuotesDontSplit() {
        XCTAssertEqual(bash("git commit -m 'a && b; c | d'"), ["Bash(git commit *)"])
        XCTAssertEqual(bash("echo \"x && y\""), ["Bash(echo \"x && y\")"])
    }

    func testCommandsWispCantReadSafelyGetNoRule() {
        XCTAssertEqual(bash("echo $(whoami)"), [])
        XCTAssertEqual(bash("echo `whoami`"), [])
        XCTAssertEqual(bash("echo \"$(whoami)\""), [])
        XCTAssertEqual(bash("(cd x && make)"), [])
        XCTAssertEqual(bash("cat <<EOF\nhi\nEOF"), [])
        XCTAssertEqual(bash("for f in a b; do echo $f; done"), [])
        XCTAssertEqual(bash("echo 'unterminated"), [])
        XCTAssertEqual(bash("npm test &&"), [])
        XCTAssertEqual(bash(""), [])
    }

    func testAnExactCommandWithAWildcardWouldMatchMoreSoItGetsNoRule() {
        XCTAssertEqual(bash("rm *.tmp"), [])
        // The prefix rule still covers it, since the wildcard is past the subcommand.
        XCTAssertEqual(bash("git add src/*.swift"), ["Bash(git add *)"])
    }

    func testTooManyPartsGetNoRule() {
        XCTAssertEqual(bash("make a; make b; make c; make d; make e; make f"), [])
    }

    func testNeverSuggestsABareTool() {
        for command in ["ls", "npm test", "rm -rf x", "git push", "a | b"] {
            for rule in bash(command) {
                XCTAssertFalse(PermissionRule.isTooBroad(rule), rule)
                XCTAssertTrue(rule.hasPrefix("Bash(") && rule.hasSuffix(")"), rule)
            }
        }
    }

    // MARK: Files

    func testAnEditInsideTheProjectAllowsItsFolder() {
        XCTAssertEqual(file("Edit", "/Users/me/app/src/views/Main.swift"), ["Edit(src/views/**)"])
        XCTAssertEqual(file("Edit", "src/x.ts"), ["Edit(src/**)"])
    }

    func testWritesAndNotebooksUseEditRules() {
        XCTAssertEqual(file("Write", "/Users/me/app/docs/a.md"), ["Edit(docs/**)"])
        XCTAssertEqual(file("MultiEdit", "/Users/me/app/docs/a.md"), ["Edit(docs/**)"])
        XCTAssertEqual(file("NotebookEdit", "/Users/me/app/nb/a.ipynb", key: "notebook_path"), ["Edit(nb/**)"])
    }

    func testReadsUseReadRules() {
        XCTAssertEqual(file("Read", "/Users/me/app/src/a.swift"), ["Read(src/**)"])
    }

    func testAFileAtTheProjectRootOrOutsideItIsMatchedExactly() {
        XCTAssertEqual(file("Edit", "/Users/me/app/README.md"), ["Edit(//Users/me/app/README.md)"])
        XCTAssertEqual(file("Edit", "/etc/hosts"), ["Edit(//etc/hosts)"])
        XCTAssertEqual(file("Edit", "/Users/me/application/x/a.txt"), ["Edit(//Users/me/application/x/a.txt)"])
    }

    func testPatternCharactersInPathsAreEscaped() {
        XCTAssertEqual(file("Edit", "/Users/me/app/[id]/page.tsx"), ["Edit(\\[id\\]/**)"])
        XCTAssertEqual(file("Edit", "/tmp/a*b.txt"), ["Edit(//tmp/a\\*b.txt)"])
    }

    func testARelativePathWithNoFolderGetsNoRule() {
        XCTAssertEqual(
            PermissionRule.suggest(tool: "Edit", input: .object(["file_path": .string("a.txt")]), cwd: ""), [])
    }

    func testDotDotCantClimbOutOfTheProject() {
        XCTAssertEqual(file("Edit", "/Users/me/app/../other/a.txt"), ["Edit(//Users/me/other/a.txt)"])
    }

    // MARK: Other tools

    func testAFetchAllowsItsDomain() {
        let input: JSONValue = .object(["url": .string("https://Docs.Example.com./guide?x=1")])
        XCTAssertEqual(
            PermissionRule.suggest(tool: "WebFetch", input: input, cwd: cwd), ["WebFetch(domain:docs.example.com)"])
        XCTAssertEqual(
            PermissionRule.suggest(tool: "WebFetch", input: .object(["url": .string("not a url")]), cwd: cwd), [])
    }

    func testAnMCPToolIsAllowedByName() {
        XCTAssertEqual(
            PermissionRule.suggest(tool: "mcp__github__get_issue", input: nil, cwd: cwd), ["mcp__github__get_issue"])
        XCTAssertEqual(PermissionRule.suggest(tool: "mcp__github", input: nil, cwd: cwd), [])
    }

    func testPlansQuestionsAndUnknownToolsGetNoRule() {
        for tool in ["ExitPlanMode", "AskUserQuestion", "Task", "WebSearch", "Grep", "Glob"] {
            XCTAssertEqual(PermissionRule.suggest(tool: tool, input: .object([:]), cwd: cwd), [], tool)
        }
    }

    // MARK: Editing

    func testTextSplitsIntoOneRulePerLine() {
        XCTAssertEqual(PermissionRule.rules(in: " Bash(a *)\n\n  Edit(src/**) \n"), ["Bash(a *)", "Edit(src/**)"])
    }

    func testProblemsWithEditedRules() {
        XCTAssertNil(PermissionRule.problem(in: ["Bash(npm test *)", "mcp__github__get_issue"]))
        XCTAssertEqual(PermissionRule.problem(in: []), "Add a rule.")
        XCTAssertEqual(
            PermissionRule.problem(in: ["Bash"]),
            "\u{201C}Bash\u{201D} allows every call. Add a pattern, such as Bash(npm test *).")
        XCTAssertNotNil(PermissionRule.problem(in: ["Bash(*)"]))
        XCTAssertNotNil(PermissionRule.problem(in: ["WebFetch(domain:*)"]))
        XCTAssertNotNil(PermissionRule.problem(in: ["mcp__github__*"]))
        XCTAssertEqual(
            PermissionRule.problem(in: ["Bash(npm"]), "\u{201C}Bash(npm\u{201D} isn't a rule. Write Tool(pattern).")
        XCTAssertNotNil(PermissionRule.problem(in: ["not a rule"]))
    }
}
