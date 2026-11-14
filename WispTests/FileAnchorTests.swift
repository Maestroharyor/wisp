import XCTest

@testable import WispCore

final class FileAnchorTests: XCTestCase {
    func testFindsTheFirstLineOfAUniqueMatch() {
        let text = "one\ntwo\nthree\nfour\n"
        XCTAssertEqual(FileAnchor.line(of: "three\nfour", in: text), 3)
        XCTAssertEqual(FileAnchor.line(of: "one", in: text), 1)
    }

    func testAMatchStartingMidLineCountsThatLine() {
        XCTAssertEqual(FileAnchor.line(of: "wo\nthr", in: "one\ntwo\nthree"), 2)
    }

    func testMissingOrAmbiguousIsNil() {
        XCTAssertNil(FileAnchor.line(of: "five", in: "one\ntwo"))
        XCTAssertNil(FileAnchor.line(of: "a", in: "a\nb\na"))
        // Overlapping copies are as ambiguous as separate ones.
        XCTAssertNil(FileAnchor.line(of: "aa", in: "x\naaa"))
        XCTAssertNil(FileAnchor.line(of: "", in: "one"))
    }

    func testWindowsLineEndingsCountOnce() {
        XCTAssertEqual(FileAnchor.line(of: "c", in: "a\r\nb\r\nc\r\n"), 3)
        XCTAssertEqual(FileAnchor.line(of: "b\r\nc", in: "a\r\nb\r\nc"), 2)
    }

    func testTextOverTheCapIsSkipped() {
        let big = String(repeating: "x\n", count: FileAnchor.maxBytes / 2 + 1) + "needle"
        XCTAssertNil(FileAnchor.line(of: "needle", in: big))
    }

    func testOnlyFilesInsideTheFolderAreRead() {
        XCTAssertTrue(FileAnchor.isInside("/Users/me/app/src/a.ts", folder: "/Users/me/app"))
        XCTAssertTrue(FileAnchor.isInside("/Users/me/app/src/a.ts", folder: "/Users/me/app/"))
        XCTAssertFalse(FileAnchor.isInside("/Users/me/app", folder: "/Users/me/app"))
        XCTAssertFalse(FileAnchor.isInside("/Users/me/apple/a.ts", folder: "/Users/me/app"))
        XCTAssertFalse(FileAnchor.isInside("/Users/me/app/../secret.txt", folder: "/Users/me/app"))
        XCTAssertFalse(FileAnchor.isInside("/etc/hosts", folder: ""))
        XCTAssertFalse(FileAnchor.isInside("relative/a.ts", folder: "/Users/me/app"))
        XCTAssertFalse(FileAnchor.isInside("/a.ts", folder: "/"))
    }

    func testAbsoluteResolvesAgainstTheFolder() {
        XCTAssertEqual(FileAnchor.absolute("src/a.ts", folder: "/Users/me/app"), "/Users/me/app/src/a.ts")
        XCTAssertEqual(FileAnchor.absolute("/tmp/a.ts", folder: "/Users/me/app"), "/tmp/a.ts")
        XCTAssertNil(FileAnchor.absolute("src/a.ts", folder: ""))
        XCTAssertNil(FileAnchor.absolute("  ", folder: "/Users/me/app"))
    }

    func testRelativePathForTheTitle() {
        XCTAssertEqual(FileAnchor.relativePath("/Users/me/app/src/auth.ts", folder: "/Users/me/app"), "src/auth.ts")
        XCTAssertEqual(FileAnchor.relativePath("/Users/me/app/src/auth.ts", folder: "/Users/me/app/"), "src/auth.ts")
        // Outside the project the home folder reads as "~".
        XCTAssertEqual(
            FileAnchor.relativePath("/Users/me/notes/a.md", folder: "/Users/me/app", home: "/Users/me"),
            "~/notes/a.md")
        XCTAssertEqual(FileAnchor.relativePath("/etc/hosts", folder: "/Users/me/app", home: "/Users/me"), "/etc/hosts")
        XCTAssertEqual(FileAnchor.relativePath("src/a.ts", folder: "/Users/me/app"), "src/a.ts")
    }

    func testTheEditTextToAnchorOn() throws {
        let edit = JSONValue.object([
            "file_path": .string("/p/a.ts"), "old_string": .string("x"), "new_string": .string("y"),
        ])
        XCTAssertEqual(FileAnchor.target(tool: "Edit", input: edit), FileAnchor.Target(path: "/p/a.ts", text: "x"))
        let one = JSONValue.object([
            "file_path": .string("/p/a.ts"),
            "edits": .array([.object(["old_string": .string("m"), "new_string": .string("n")])]),
        ])
        XCTAssertEqual(FileAnchor.target(tool: "MultiEdit", input: one)?.text, "m")
        // Several edits anchor at different places, so none is numbered.
        let two = JSONValue.object([
            "file_path": .string("/p/a.ts"),
            "edits": .array([
                .object(["old_string": .string("m"), "new_string": .string("n")]),
                .object(["old_string": .string("o"), "new_string": .string("p")]),
            ]),
        ])
        XCTAssertNil(FileAnchor.target(tool: "MultiEdit", input: two))
        // Replacing every copy has no one place.
        var all = edit
        if case .object(var fields) = all {
            fields["replace_all"] = .bool(true)
            all = .object(fields)
        }
        XCTAssertNil(FileAnchor.target(tool: "Edit", input: all))
        XCTAssertNil(FileAnchor.target(tool: "Edit", input: .object(["file_path": .string("/p/a.ts")])))
        XCTAssertNil(FileAnchor.target(tool: "Write", input: edit))
        XCTAssertNil(FileAnchor.target(tool: "Bash", input: edit))
    }

    func testShiftingRelativeNumbers() {
        XCTAssertEqual(FileAnchor.shift(1, anchor: 40), 40)
        XCTAssertEqual(FileAnchor.shift(3, anchor: 40), 42)
        XCTAssertNil(FileAnchor.shift(nil, anchor: 40))
        XCTAssertNil(FileAnchor.shift(3, anchor: nil))
    }
}
