import XCTest

@testable import WispCore

final class ShortcutMapTests: XCTestCase {
    private let hyper = Hotkey.hyperSpace
    private let plain = Hotkey(keyCode: KeyCodes.space, modifiers: [.shift, .command])

    private func key(_ code: UInt16, _ modifiers: Hotkey.Modifiers) -> Hotkey {
        Hotkey(keyCode: code, modifiers: modifiers)
    }

    func testTheDefaultsMatchTodaysKeysWithCapsLock() {
        let map = ShortcutMap()
        XCTAssertEqual(map.key(for: .ring, shelf: hyper), key(KeyCodes.r, .hyper))
        XCTAssertEqual(map.key(for: .cycleForm, shelf: hyper), key(KeyCodes.f, .hyper))
        XCTAssertEqual(map.key(for: .clipboard, shelf: hyper), Hotkey.clipboardHyper)
        XCTAssertEqual(map.key(for: .sessionSwitcher, shelf: hyper), Hotkey.switcherHyper)
    }

    func testWithoutCapsLockEachActionHasAFallback() {
        let map = ShortcutMap()
        XCTAssertEqual(map.key(for: .clipboard, shelf: plain), Hotkey.clipboardFallback)
        XCTAssertEqual(map.key(for: .sessionSwitcher, shelf: plain), Hotkey.switcherFallback)
        XCTAssertEqual(map.key(for: .ring, shelf: plain), key(KeyCodes.r, [.control, .option, .command]))
        XCTAssertEqual(map.key(for: .cycleForm, shelf: plain), key(KeyCodes.f, [.control, .option, .command]))
    }

    func testAShelfOnAnActionsHyperKeyMovesThatActionToItsFallback() {
        // The shelf on Hyper+G used to take the switcher's chord; any action now moves aside.
        for action in ShortcutAction.allCases {
            let standard = ShortcutMap().key(for: action, shelf: hyper)
            let shelf = key(standard?.keyCode ?? 0, .hyper)
            let moved = ShortcutMap().key(for: action, shelf: shelf)
            XCTAssertNotEqual(moved, shelf, "\(action)")
            XCTAssertFalse(moved?.usesHyper ?? true, "\(action)")
        }
    }

    func testACustomKeyWinsAndCanBeTurnedOff() {
        var map = ShortcutMap()
        map.set(key(40, .hyper), for: .ring)
        XCTAssertEqual(map.key(for: .ring, shelf: hyper), key(40, .hyper))
        map.set(nil, for: .cycleForm)
        XCTAssertNil(map.key(for: .cycleForm, shelf: hyper))
        XCTAssertTrue(map.isCustom(.cycleForm))
        map.reset(.ring)
        XCTAssertFalse(map.isCustom(.ring))
        XCTAssertEqual(map.key(for: .ring, shelf: hyper), key(KeyCodes.r, .hyper))
    }

    func testItRoundTripsThroughStorage() {
        var map = ShortcutMap()
        map.set(key(40, [.command, .option]), for: .clipboard)
        map.set(nil, for: .ring)
        let stored = map.stored
        XCTAssertEqual(stored["ring"], "")
        XCTAssertEqual(ShortcutMap(stored: stored), map)
    }

    func testBrokenStorageFallsBackToTheDefault() {
        let map = ShortcutMap(stored: ["ring": "nonsense+key", "unknown": "cmd+k"])
        XCTAssertFalse(map.isCustom(.ring))
        XCTAssertEqual(map, ShortcutMap())
    }

    func testAKeyAnotherShortcutUsesIsAClash() {
        let map = ShortcutMap()
        XCTAssertEqual(
            map.clash(key(KeyCodes.v, .hyper), for: .ring, shelf: hyper, holdKey: nil), "Clipboard history")
        XCTAssertEqual(map.clash(hyper, for: .ring, shelf: hyper, holdKey: nil), "Open or close the shelf")
        XCTAssertNil(map.clash(key(KeyCodes.r, .hyper), for: .ring, shelf: hyper, holdKey: nil))
        XCTAssertNil(map.clash(key(40, .hyper), for: .ring, shelf: hyper, holdKey: nil))
    }

    func testCapsLockKeysWispAlreadyUsesAreTaken() {
        let map = ShortcutMap()
        XCTAssertEqual(
            map.clash(key(ApprovalKeys.yes, .hyper), for: .ring, shelf: hyper, holdKey: nil),
            "Allow, or send an answer")
        XCTAssertEqual(map.clash(key(ApprovalKeys.no, .hyper), for: .ring, shelf: hyper, holdKey: nil), "Deny")
        XCTAssertEqual(
            map.clash(key(ApprovalKeys.digits[2], .hyper), for: .ring, shelf: hyper, holdKey: nil),
            "Pick an answer or switch profile")
        XCTAssertEqual(map.clash(key(40, .hyper), for: .ring, shelf: hyper, holdKey: 40), "Dictation")
        // Without Caps Lock those letters are free.
        XCTAssertNil(map.clash(key(ApprovalKeys.yes, [.command, .option]), for: .ring, shelf: hyper, holdKey: nil))
    }

    func testClashesListsEveryActionSharingAKey() {
        var map = ShortcutMap()
        map.set(key(KeyCodes.v, .hyper), for: .ring)
        XCTAssertEqual(Set(map.clashes(shelf: hyper, holdKey: nil)), [.ring, .clipboard])
        XCTAssertTrue(ShortcutMap().clashes(shelf: hyper, holdKey: nil).isEmpty)
    }
}
