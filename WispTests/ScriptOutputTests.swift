import XCTest

@testable import WispCore

final class ScriptOutputTests: XCTestCase {
    func testKeepsTheFirstNonEmptyLines() {
        XCTAssertEqual(
            ScriptOutput.lines(from: "\nfirst\n\n second \nthird\nfourth\n", limit: 3),
            [
                "first", "second", "third",
            ])
    }

    func testStripsTerminalColours() {
        XCTAssertEqual(ScriptOutput.lines(from: "\u{1B}[32mOK\u{1B}[0m 12 ms", limit: 3), ["OK 12 ms"])
    }

    func testTrimsVeryLongLines() {
        let line = String(repeating: "a", count: 300)
        XCTAssertEqual(ScriptOutput.lines(from: line, limit: 1).first?.count, ScriptOutput.maxLineLength)
    }

    func testIntervalStaysSensible() {
        XCTAssertEqual(ScriptOutput.clampedInterval(1), 10)
        XCTAssertEqual(ScriptOutput.clampedInterval(90), 90)
        XCTAssertEqual(ScriptOutput.clampedInterval(99_999), 3600)
    }
}
