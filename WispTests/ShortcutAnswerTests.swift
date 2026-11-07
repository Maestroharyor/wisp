import XCTest

@testable import WispCore

final class ShortcutAnswerTests: XCTestCase {
    private let bash = ShortcutAnswer.Request(agent: "Claude Code", tool: "Bash", project: "wisp", prompt: .tool)

    func testOnlyAFrontToolRequestIsAnswered() {
        XCTAssertEqual(ShortcutAnswer.pick(front: .tool), .answer)
        XCTAssertEqual(ShortcutAnswer.pick(front: nil), .refuse(ShortcutAnswer.nothingWaiting))
    }

    // A Shortcut must never skip past the card on screen to answer one the user can't see.
    func testPlansAndQuestionsAtTheFrontAreRefused() {
        XCTAssertEqual(ShortcutAnswer.pick(front: .plan), .refuse("Answer this one in the notch."))
        XCTAssertEqual(ShortcutAnswer.pick(front: .question), .refuse("Answer this one in the notch."))
    }

    func testConfirmationNamesAgentActionToolAndProject() {
        XCTAssertEqual(
            ShortcutAnswer.confirmation(bash, allow: true, hidden: false),
            "Claude Code wants to run a command (Bash) in wisp.\nAllow it?")
        XCTAssertEqual(
            ShortcutAnswer.confirmation(bash, allow: false, hidden: false),
            "Claude Code wants to run a command (Bash) in wisp.\nDeny it?")
    }

    func testConfirmationShowsWhatRunsMasked() {
        let command = ShortcutAnswer.Request(
            agent: "Claude Code", tool: "Bash", project: "wisp", prompt: .tool,
            summary: "TOKEN=abc npm test\necho second line")
        XCTAssertEqual(
            ShortcutAnswer.confirmation(command, allow: true, hidden: false),
            "Claude Code wants to run a command (Bash) in wisp.\nTOKEN=••• npm test\nAllow it?")
        let edit = ShortcutAnswer.Request(
            agent: "Codex", tool: "Edit", project: "wisp", prompt: .tool, summary: "/Users/me/wisp/src/App.swift")
        XCTAssertEqual(
            ShortcutAnswer.confirmation(edit, allow: false, hidden: false),
            "Codex wants to edit a file (Edit) in wisp.\nApp.swift\nDeny it?")
        XCTAssertEqual(
            ShortcutAnswer.confirmation(command, allow: true, hidden: true),
            "Claude Code wants to run a command (Bash).\nAllow it?")
    }

    func testPrivateModeLeavesTheProjectOut() {
        XCTAssertEqual(
            ShortcutAnswer.confirmation(bash, allow: true, hidden: true),
            "Claude Code wants to run a command (Bash).\nAllow it?")
        XCTAssertEqual(
            ShortcutAnswer.result(bash, allow: false, hidden: true), "Denied Claude Code's request to run a command.")
    }

    func testResultNamesTheProjectWhenAllowed() {
        XCTAssertEqual(
            ShortcutAnswer.result(bash, allow: true, hidden: false), "Allowed Claude Code to run a command in wisp.")
        let empty = ShortcutAnswer.Request(agent: "Codex", tool: "Edit", project: "", prompt: .tool)
        XCTAssertEqual(ShortcutAnswer.result(empty, allow: true, hidden: false), "Allowed Codex to edit a file.")
    }
}
