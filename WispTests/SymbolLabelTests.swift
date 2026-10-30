import XCTest

@testable import WispCore

final class SymbolLabelTests: XCTestCase {
    func testKnownSymbolsReadAsActions() {
        XCTAssertEqual(SymbolLabel.label(for: "play.fill"), "Play")
        XCTAssertEqual(SymbolLabel.label(for: "pause.fill"), "Pause")
        XCTAssertEqual(SymbolLabel.label(for: "forward.fill"), "Next")
        XCTAssertEqual(SymbolLabel.label(for: "backward.fill"), "Previous")
        XCTAssertEqual(SymbolLabel.label(for: "xmark"), "Close")
        XCTAssertEqual(SymbolLabel.label(for: "arrow.counterclockwise"), "Reset")
        XCTAssertEqual(SymbolLabel.label(for: "pip"), "Mini player")
    }

    func testUnknownSymbolsFallBackToReadableWords() {
        XCTAssertEqual(SymbolLabel.label(for: "speaker.wave.2.fill"), "Speaker wave 2")
        XCTAssertEqual(SymbolLabel.label(for: "chevron.up"), "Chevron up")
    }
}
