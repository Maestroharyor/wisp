import XCTest

@testable import WispCore

final class HotkeyTests: XCTestCase {
    func testHyperSpaceRoundTrips() {
        XCTAssertEqual(Hotkey.hyperSpace.stringValue, "hyper+space")
        XCTAssertEqual(Hotkey(string: "hyper+space"), .hyperSpace)
        XCTAssertEqual(Hotkey(string: "Caps+Space"), .hyperSpace)
        XCTAssertTrue(Hotkey.hyperSpace.usesHyper)
        XCTAssertEqual(Hotkey.hyperSpace.description, "⇪ Space")
    }

    func testStandardShortcut() {
        let hotkey = Hotkey(string: "shift+cmd+k")
        XCTAssertEqual(hotkey, Hotkey(keyCode: 40, modifiers: [.command, .shift]))
        XCTAssertEqual(hotkey?.stringValue, "shift+cmd+k")
        XCTAssertEqual(hotkey?.description, "⇧⌘K")
        XCTAssertEqual(hotkey?.usesHyper, false)
    }

    func testRejectsInvalidStrings() {
        XCTAssertNil(Hotkey(string: "space"), "needs a modifier")
        XCTAssertNil(Hotkey(string: "cmd+space+k"), "only one key")
        XCTAssertNil(Hotkey(string: "cmd+banana"))
        XCTAssertNil(Hotkey(string: ""))
    }

    func testEveryNamedKeyRoundTrips() {
        for name in ["a", "z", "0", "9", "space", "return", "tab", "escape", "up"] {
            guard let code = KeyCodes.code(for: name) else {
                return XCTFail("missing key \(name)")
            }
            XCTAssertEqual(KeyCodes.name(for: code), name)
        }
    }

    func testClipboardShortcuts() {
        XCTAssertEqual(KeyCodes.v, 9)
        XCTAssertEqual(Hotkey.clipboardHyper, Hotkey(keyCode: 9, modifiers: .hyper))
        XCTAssertEqual(Hotkey.clipboardFallback.description, "⌥⇧⌘V")
        XCTAssertFalse(Hotkey.clipboardFallback.usesHyper)
    }
}
