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

    func testShiftAloneOnlyWorksOnFunctionKeys() throws {
        let s = try XCTUnwrap(KeyCodes.code(for: "s"))
        XCTAssertFalse(Hotkey(keyCode: s, modifiers: .shift).isUsable, "would swallow every capital S")
        XCTAssertNil(Hotkey(string: "shift+s"))
        XCTAssertTrue(Hotkey(keyCode: s, modifiers: [.shift, .option]).isUsable)
        XCTAssertTrue(Hotkey(keyCode: 96, modifiers: .shift).isUsable, "⇧F5")
        XCTAssertTrue(Hotkey.hyperSpace.isUsable)
    }

    func testEveryNamedKeyRoundTrips() {
        for name in ["a", "z", "0", "9", "space", "return", "tab", "escape", "up"] {
            guard let code = KeyCodes.code(for: name) else {
                return XCTFail("missing key \(name)")
            }
            XCTAssertEqual(KeyCodes.name(for: code), name)
        }
    }

    func testKeysOutsideTheTableRoundTrip() {
        let f5 = Hotkey(keyCode: 96, modifiers: [.command, .shift])
        XCTAssertEqual(f5.stringValue, "shift+cmd+key96")
        XCTAssertEqual(Hotkey(string: f5.stringValue), f5)
        XCTAssertNil(Hotkey(string: "cmd+key"))
        XCTAssertNil(Hotkey(string: "cmd+key99999"))
    }

    func testClipboardShortcuts() {
        XCTAssertEqual(KeyCodes.v, 9)
        XCTAssertEqual(Hotkey.clipboardHyper, Hotkey(keyCode: 9, modifiers: .hyper))
        XCTAssertEqual(Hotkey.clipboardFallback.description, "⌥⇧⌘V")
        XCTAssertFalse(Hotkey.clipboardFallback.usesHyper)
    }
}
