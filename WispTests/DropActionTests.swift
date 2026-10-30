import XCTest

@testable import WispCore

final class DropActionTests: XCTestCase {
    func testSplitsLikeAShellWithoutRunningOne() {
        XCTAssertEqual(
            CommandLineText.split("magick {file} -resize 50% out.png"),
            [
                "magick", "{file}", "-resize", "50%", "out.png",
            ])
        XCTAssertEqual(CommandLineText.split(#"say "hello there" 'and more'"#), ["say", "hello there", "and more"])
        XCTAssertEqual(CommandLineText.split(#"echo a\ b"#), ["echo", "a b"])
        XCTAssertEqual(CommandLineText.split("  spaced   out  "), ["spaced", "out"])
    }

    func testShellSyntaxStaysLiteral() {
        // No pipes, globbing or substitution: they arrive as plain arguments.
        XCTAssertEqual(CommandLineText.split("echo $(rm -rf ~) | cat"), ["echo", "$(rm", "-rf", "~)", "|", "cat"])
    }

    func testUnclosedQuotesAreRejected() {
        XCTAssertNil(CommandLineText.split(#"say "oops"#))
    }

    func testFilesPlaceholderExpandsToEveryPath() throws {
        let action = DropAction(name: "Open in", kind: .command("open -a Preview {files}"))
        let runs = try XCTUnwrap(action.invocations(for: ["/a b/1.png", "/c/2.png"]))
        XCTAssertEqual(runs, [["/usr/bin/env", "open", "-a", "Preview", "/a b/1.png", "/c/2.png"]])
    }

    func testFilePlaceholderRunsOncePerFile() throws {
        let action = DropAction(name: "Shrink", kind: .command("sips -Z 800 {file}"))
        let runs = try XCTUnwrap(action.invocations(for: ["/a.png", "/b.png"]))
        XCTAssertEqual(
            runs, [["/usr/bin/env", "sips", "-Z", "800", "/a.png"], ["/usr/bin/env", "sips", "-Z", "800", "/b.png"]])
    }

    func testNoPlaceholderAppendsTheFiles() throws {
        let action = DropAction(name: "Upload", kind: .command("/usr/local/bin/upload --public"))
        let runs = try XCTUnwrap(action.invocations(for: ["/a.png"]))
        XCTAssertEqual(runs, [["/usr/local/bin/upload", "--public", "/a.png"]])
    }

    func testPlaceholderInsideAnArgument() throws {
        let action = DropAction(name: "Copy", kind: .command("cp {file} --target={file}.bak"))
        let runs = try XCTUnwrap(action.invocations(for: ["/x"]))
        XCTAssertEqual(runs, [["/usr/bin/env", "cp", "/x", "--target=/x.bak"]])
    }

    func testShortcutGetsEachFileAsInput() throws {
        let action = DropAction(name: "Resize", kind: .shortcut("Resize Images"))
        let runs = try XCTUnwrap(action.invocations(for: ["/a.png", "/b.png"]))
        XCTAssertEqual(runs, [["/usr/bin/shortcuts", "run", "Resize Images", "-i", "/a.png", "-i", "/b.png"]])
    }

    func testInvalidActionsProduceNothing() {
        XCTAssertNil(DropAction(name: "Empty", kind: .command("   ")).invocations(for: ["/a"]))
        XCTAssertNil(DropAction(name: "Broken", kind: .command(#"say "x"#)).invocations(for: ["/a"]))
        XCTAssertNil(DropAction(name: "No shortcut", kind: .shortcut("")).invocations(for: ["/a"]))
        XCTAssertNil(DropAction(name: "No files", kind: .command("ls {files}")).invocations(for: []))
    }

    func testValidationMessages() {
        XCTAssertNil(DropAction(name: "Ok", kind: .command("ls {files}")).problem)
        XCTAssertEqual(DropAction(name: "", kind: .command("ls")).problem, "Give the action a name.")
        XCTAssertEqual(DropAction(name: "A", kind: .command("")).problem, "Type a command.")
        XCTAssertEqual(DropAction(name: "A", kind: .command(#"say "x"#)).problem, "Close the quote.")
        XCTAssertEqual(DropAction(name: "A", kind: .shortcut("")).problem, "Choose a Shortcut.")
    }

    func testRoundTripsThroughJSON() throws {
        let actions = [
            DropAction(
                name: "Shrink", symbol: "arrow.down.right.and.arrow.up.left", kind: .command("sips -Z 800 {file}")),
            DropAction(name: "Resize", kind: .shortcut("Resize Images")),
        ]
        let decoded = try JSONDecoder().decode([DropAction].self, from: JSONEncoder().encode(actions))
        XCTAssertEqual(decoded, actions)
    }
}
