import XCTest

@testable import WispCore

final class ApprovalPreviewTests: XCTestCase {
    private func input(_ fields: [String: String]) -> JSONValue { .object(fields.mapValues(JSONValue.string)) }

    func testAnEditShowsOnlyTheLinesThatChangeWithContext() {
        let old = "a\nb\nc\nd\ne"
        let new = "a\nb\nC\nd\ne"
        let preview = ApprovalPreview.make(
            tool: "Edit", input: input(["file_path": "/p/x.swift", "old_string": old, "new_string": new]), limit: 20)
        XCTAssertEqual(
            preview,
            .diff(
                [
                    DiffLine(kind: .context, text: "b"), DiffLine(kind: .removed, text: "c"),
                    DiffLine(kind: .added, text: "C"), DiffLine(kind: .context, text: "d"),
                ], more: 0))
    }

    func testALongEditIsCappedAndCountsTheRest() {
        let old = (1...30).map { "old \($0)" }.joined(separator: "\n")
        let new = (1...30).map { "new \($0)" }.joined(separator: "\n")
        guard
            case .diff(let lines, let more) = ApprovalPreview.make(
                tool: "Edit", input: input(["old_string": old, "new_string": new]), limit: 10)
        else { return XCTFail("expected a diff") }
        XCTAssertEqual(lines.count, 10)
        XCTAssertEqual(more, 50)
        XCTAssertEqual(lines.first, DiffLine(kind: .removed, text: "old 1"))
    }

    func testAnEmptySideIsNoLines() {
        XCTAssertEqual(
            ApprovalPreview.make(tool: "Edit", input: input(["old_string": "", "new_string": "x"]), limit: 5),
            .diff([DiffLine(kind: .added, text: "x")], more: 0))
    }

    func testAMultiEditShowsEveryEdit() {
        let edits: JSONValue = .array([
            .object(["old_string": .string("a"), "new_string": .string("b")]),
            .object(["old_string": .string("c"), "new_string": .string("d")]),
        ])
        XCTAssertEqual(
            ApprovalPreview.make(tool: "MultiEdit", input: .object(["edits": edits]), limit: 10),
            .diff(
                [
                    DiffLine(kind: .removed, text: "a"), DiffLine(kind: .added, text: "b"),
                    DiffLine(kind: .removed, text: "c"), DiffLine(kind: .added, text: "d"),
                ], more: 0))
    }

    func testACodexPatchReadsAsADiff() {
        let patch = "*** Begin Patch\n*** Update File: a.py\n@@\n-old\n+new\n keep\n*** End Patch"
        XCTAssertEqual(
            ApprovalPreview.make(tool: "apply_patch", input: input(["command": patch]), limit: 10),
            .diff(
                [
                    DiffLine(kind: .context, text: "*** Update File: a.py"), DiffLine(kind: .context, text: "@@"),
                    DiffLine(kind: .removed, text: "old"), DiffLine(kind: .added, text: "new"),
                    DiffLine(kind: .context, text: "keep"),
                ], more: 0))
    }

    func testAWriteShowsItsFirstLines() {
        let content = (1...50).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(
            ApprovalPreview.make(tool: "Write", input: input(["content": content]), limit: 3),
            .text("line 1\nline 2\nline 3", more: 47))
    }

    func testACommandShowsInFull() {
        XCTAssertEqual(
            ApprovalPreview.make(tool: "Bash", input: input(["command": "npm test && npm run build"]), limit: 3),
            .text("npm test && npm run build", more: 0))
    }

    func testAPlanIsMarkdown() {
        XCTAssertEqual(
            ApprovalPreview.make(tool: "ExitPlanMode", input: input(["plan": "# Plan\n\n- one"]), limit: 3),
            .markdown("# Plan\n\n- one"))
    }

    func testOtherToolsAndEmptyInputHaveNoPreview() {
        XCTAssertNil(ApprovalPreview.make(tool: "Read", input: input(["file_path": "/p/x"]), limit: 5))
        XCTAssertNil(ApprovalPreview.make(tool: "Edit", input: nil, limit: 5))
        XCTAssertNil(ApprovalPreview.make(tool: "Bash", input: input(["command": "  "]), limit: 5))
    }

    func testADenialCarriesTheReason() {
        XCTAssertEqual(
            PermissionReply.denial(for: .tool, reason: " use pnpm "), "Denied from the Wisp notch: use pnpm")
        XCTAssertEqual(PermissionReply.denial(for: .tool, reason: ""), "Denied from the Wisp notch.")
        XCTAssertEqual(
            PermissionReply.denial(for: .plan, reason: "split it in two"),
            PermissionReply.planDenied + " What to change: split it in two")
        XCTAssertEqual(PermissionReply.denial(for: .plan, reason: " "), PermissionReply.planDenied)
    }
}
