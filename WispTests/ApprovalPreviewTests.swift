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
                    DiffLine(kind: .hunk, text: "Edit 1 of 2"), DiffLine(kind: .removed, text: "a"),
                    DiffLine(kind: .added, text: "b"), DiffLine(kind: .hunk, text: "Edit 2 of 2"),
                    DiffLine(kind: .removed, text: "c"), DiffLine(kind: .added, text: "d"),
                ], more: 0))
    }

    func testAnEditIsAUnifiedDiffWithItsChangesInPlace() {
        let old = "a\nb\nc\nd\ne\nf\ng"
        let new = "a\nB\nc\nd\ne\nF\ng"
        XCTAssertEqual(
            ApprovalPreview.make(tool: "Edit", input: input(["old_string": old, "new_string": new]), limit: 40),
            .diff(
                [
                    DiffLine(kind: .context, text: "a"), DiffLine(kind: .removed, text: "b"),
                    DiffLine(kind: .added, text: "B"), DiffLine(kind: .context, text: "c"),
                    DiffLine(kind: .hunk, text: "⋯"),
                    DiffLine(kind: .context, text: "e"), DiffLine(kind: .removed, text: "f"),
                    DiffLine(kind: .added, text: "F"), DiffLine(kind: .context, text: "g"),
                ], more: 0))
    }

    func testCloseChangesShareAHunk() {
        let old = "a\nb\nc\nd"
        let new = "A\nb\nC\nd"
        XCTAssertEqual(
            ApprovalPreview.make(tool: "Edit", input: input(["old_string": old, "new_string": new]), limit: 40),
            .diff(
                [
                    DiffLine(kind: .removed, text: "a"), DiffLine(kind: .added, text: "A"),
                    DiffLine(kind: .context, text: "b"), DiffLine(kind: .removed, text: "c"),
                    DiffLine(kind: .added, text: "C"), DiffLine(kind: .context, text: "d"),
                ], more: 0))
    }

    func testUnifiedAgreesWithTheChangeCounts() {
        let old = (1...20).map { "line \($0)" }
        var new = old
        new[3] = "changed"
        new.insert("inserted", at: 10)
        new.remove(at: 15)
        let lines = LineDiff.unified(old: old, new: new, context: 1)
        let changes = LineDiff.changes(old: old, new: new)
        XCTAssertEqual(lines.filter { $0.kind == .removed }.map(\.text), changes.removed)
        XCTAssertEqual(lines.filter { $0.kind == .added }.map(\.text), changes.added)
    }

    func testACodexPatchIsShownAsIsWithItsHeaders() {
        let patch = "*** Begin Patch\n*** Update File: a.py\n@@\n-old\n+new\n keep\n*** End Patch"
        XCTAssertEqual(
            ApprovalPreview.make(tool: "apply_patch", input: input(["command": patch]), limit: 10),
            .diff(
                [
                    DiffLine(kind: .hunk, text: "*** Update File: a.py"), DiffLine(kind: .hunk, text: "@@"),
                    DiffLine(kind: .removed, text: "old"), DiffLine(kind: .added, text: "new"),
                    DiffLine(kind: .context, text: "keep"),
                ], more: 0))
    }

    func testTheFileNameForPrivateMode() {
        XCTAssertEqual(
            InlineDiff.fileName(tool: "Edit", input: input(["file_path": "/Users/me/app/src/main.swift"])), "main.swift"
        )
        XCTAssertEqual(InlineDiff.fileName(tool: "Write", input: input(["file_path": "notes.md"])), "notes.md")
        let patch = "*** Begin Patch\n*** Update File: src/a.py\n@@\n-x\n+y\n*** End Patch"
        XCTAssertEqual(InlineDiff.fileName(tool: "apply_patch", input: input(["command": patch])), "a.py")
        let two = "*** Begin Patch\n*** Add File: a.py\n+x\n*** Delete File: b.py\n*** End Patch"
        XCTAssertEqual(InlineDiff.fileName(tool: "apply_patch", input: input(["command": two])), "a.py +1")
        XCTAssertNil(InlineDiff.fileName(tool: "Bash", input: input(["command": "ls"])))
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

    func testOpenCodesBashRequestShowsItsCommand() {
        XCTAssertEqual(
            ApprovalPreview.make(tool: "bash", input: input(["command": "npm test"]), limit: 3),
            .text("npm test", more: 0))
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
