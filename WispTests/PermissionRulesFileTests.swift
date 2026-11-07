import XCTest

@testable import WispCore

final class PermissionRulesFileTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private func decode(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    private func list(_ items: String...) -> JSONValue { .array(items.map(JSONValue.string)) }

    func testAddingToNoFileCreatesTheStructure() throws {
        let updated = try PermissionRulesFile.adding(["Bash(npm test *)"], to: Data())
        XCTAssertEqual(try decode(updated), .object(["permissions": .object(["allow": list("Bash(npm test *)")])]))
    }

    func testAddingKeepsTheUsersOrderAndOtherKeys() throws {
        let original = data(
            """
            {"model": "opus", "hooks": {"Stop": []},
             "permissions": {"allow": ["Read(src/**)", "Bash(ls)"], "deny": ["Bash(rm *)"], "ask": ["Bash(git push *)"],
                             "defaultMode": "acceptEdits"}}
            """)
        let updated = try decode(PermissionRulesFile.adding(["Bash(make test *)"], to: original))
        XCTAssertEqual(updated["model"], .string("opus"))
        XCTAssertEqual(updated["hooks"], .object(["Stop": .array([])]))
        XCTAssertEqual(updated["permissions"]?["allow"], list("Read(src/**)", "Bash(ls)", "Bash(make test *)"))
        XCTAssertEqual(updated["permissions"]?["deny"], list("Bash(rm *)"))
        XCTAssertEqual(updated["permissions"]?["ask"], list("Bash(git push *)"))
        XCTAssertEqual(updated["permissions"]?["defaultMode"], .string("acceptEdits"))
    }

    func testAddingSkipsRulesAlreadyThere() throws {
        let original = data(#"{"permissions": {"allow": ["Bash(ls)"]}}"#)
        let updated = try decode(PermissionRulesFile.adding(["Bash(ls)", "Bash(pwd)", "Bash(pwd)"], to: original))
        XCTAssertEqual(updated["permissions"]?["allow"], list("Bash(ls)", "Bash(pwd)"))
    }

    func testAddingWithPermissionsButNoAllowList() throws {
        let original = data(#"{"permissions": {"deny": ["Bash(rm *)"]}}"#)
        let updated = try decode(PermissionRulesFile.adding(["Bash(ls)"], to: original))
        XCTAssertEqual(updated["permissions"]?["allow"], list("Bash(ls)"))
        XCTAssertEqual(updated["permissions"]?["deny"], list("Bash(rm *)"))
    }

    func testNonStringEntriesTheUserWroteStay() throws {
        let original = data(#"{"permissions": {"allow": [42, "Bash(ls)"]}}"#)
        let updated = try decode(PermissionRulesFile.adding(["Bash(pwd)"], to: original))
        XCTAssertEqual(
            updated["permissions"]?["allow"], .array([.number(42), .string("Bash(ls)"), .string("Bash(pwd)")]))
    }

    func testOutputIsPrettyWithSortedKeys() throws {
        let updated = try PermissionRulesFile.adding(["Edit(src/**)"], to: data(#"{"z": 1, "a": 2}"#))
        let text = String(decoding: updated, as: UTF8.self)
        XCTAssertTrue(text.contains("\n"))
        let a = try XCTUnwrap(text.range(of: "\"a\""))
        let z = try XCTUnwrap(text.range(of: "\"z\""))
        XCTAssertLessThan(a.lowerBound, z.lowerBound)
        XCTAssertTrue(text.contains("Edit(src/**)"), "slashes aren't escaped")
    }

    func testMalformedJSONIsRefused() {
        XCTAssertThrowsError(try PermissionRulesFile.adding(["Bash(ls)"], to: data("{ not json")))
        XCTAssertThrowsError(try PermissionRulesFile.lists(in: data("{ not json")))
    }

    func testAFileThatIsntAnObjectIsRefused() {
        XCTAssertThrowsError(try PermissionRulesFile.adding(["Bash(ls)"], to: data("[1, 2]"))) {
            XCTAssertEqual($0 as? PermissionRulesFile.Failure, .notAnObject)
        }
        XCTAssertThrowsError(try PermissionRulesFile.adding(["Bash(ls)"], to: data(#""text""#)))
    }

    func testOddlyShapedPermissionsAreRefusedRatherThanReplaced() {
        XCTAssertThrowsError(try PermissionRulesFile.adding(["Bash(ls)"], to: data(#"{"permissions": []}"#))) {
            XCTAssertEqual($0 as? PermissionRulesFile.Failure, .permissionsNotAnObject)
        }
        XCTAssertThrowsError(
            try PermissionRulesFile.adding(["Bash(ls)"], to: data(#"{"permissions": {"allow": "Bash(ls)"}}"#))
        ) {
            XCTAssertEqual($0 as? PermissionRulesFile.Failure, .listNotAnArray("allow"))
        }
    }

    func testListsReadsAllowAskAndDeny() throws {
        let original = data(
            #"{"permissions": {"allow": ["Bash(ls)", 3], "ask": ["Bash(git push *)"], "deny": ["Read(.env)"]}}"#)
        XCTAssertEqual(
            try PermissionRulesFile.lists(in: original),
            PermissionRulesFile.Lists(allow: ["Bash(ls)"], ask: ["Bash(git push *)"], deny: ["Read(.env)"]))
        XCTAssertEqual(try PermissionRulesFile.lists(in: Data()), PermissionRulesFile.Lists())
        XCTAssertEqual(try PermissionRulesFile.lists(in: data("{}")).isEmpty, true)
    }

    func testRemovingTakesOutOneAllowEntryOnly() throws {
        let original = data(
            #"{"permissions": {"allow": ["Bash(ls)", "Bash(pwd)"], "deny": ["Bash(ls)"]}, "model": "opus"}"#)
        let updated = try decode(PermissionRulesFile.removing("Bash(ls)", from: original))
        XCTAssertEqual(updated["permissions"]?["allow"], list("Bash(pwd)"))
        XCTAssertEqual(updated["permissions"]?["deny"], list("Bash(ls)"))
        XCTAssertEqual(updated["model"], .string("opus"))
    }

    func testRemovingTheLastEntryLeavesAnEmptyList() throws {
        let updated = try decode(
            PermissionRulesFile.removing("Bash(ls)", from: data(#"{"permissions": {"allow": ["Bash(ls)"]}}"#)))
        XCTAssertEqual(updated["permissions"]?["allow"], .array([]))
    }

    func testRemovingFromMalformedJSONIsRefused() {
        XCTAssertThrowsError(try PermissionRulesFile.removing("Bash(ls)", from: data("nope")))
        XCTAssertThrowsError(try PermissionRulesFile.removing("Bash(ls)", from: data("[]")))
    }

    // MARK: Where rules go

    private func reader(_ files: [String: String]) -> (String) -> String? { { files[$0] } }

    func testEverywhereIsTheUserSettings() {
        XCTAssertEqual(
            PermissionRulesFile.path(for: .everywhere, cwd: "/p", home: "/Users/me", read: reader([:])),
            "/Users/me/.claude/settings.json")
    }

    func testThisProjectIsTheRepositoryRootsLocalSettings() {
        let read = reader(["/Users/me/app/.git/HEAD": "ref: refs/heads/main"])
        XCTAssertEqual(
            PermissionRulesFile.path(for: .project, cwd: "/Users/me/app/packages/api", home: "/Users/me", read: read),
            "/Users/me/app/.claude/settings.local.json")
    }

    func testAWorktreeUsesTheMainCheckout() {
        let read = reader(["/Users/me/wt/feature/.git": "gitdir: /Users/me/app/.git/worktrees/feature"])
        XCTAssertEqual(
            PermissionRulesFile.projectRoot(cwd: "/Users/me/wt/feature/src", read: read), "/Users/me/app")
    }

    func testOutsideARepositoryTheFolderItselfIsUsed() {
        XCTAssertEqual(
            PermissionRulesFile.projectRoot(cwd: "/Users/me/scratch", read: reader([:])), "/Users/me/scratch")
        XCTAssertNil(PermissionRulesFile.projectRoot(cwd: "", read: reader([:])))
        XCTAssertNil(PermissionRulesFile.path(for: .project, cwd: "", home: "/Users/me", read: reader([:])))
    }

    func testOnlyUserSettingsKeepCopies() {
        XCTAssertTrue(RuleScope.everywhere.keepsCopies)
        XCTAssertFalse(RuleScope.project.keepsCopies)
    }
}
