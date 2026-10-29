import XCTest

@testable import WispCore

final class KeyMappingTests: XCTestCase {
    func testParsesNull() {
        XCTAssertEqual(KeyMappingCodec.parse("(null)\n"), [])
    }

    func testParsesHidutilOutput() {
        let output = """
            (
                    {
                    HIDKeyboardModifierMappingDst = 30064771181;
                    HIDKeyboardModifierMappingSrc = 30064771129;
                },
                    {
                    HIDKeyboardModifierMappingDst = 0x700000035;
                    HIDKeyboardModifierMappingSrc = 0x700000064;
                }
            )
            """
        XCTAssertEqual(
            KeyMappingCodec.parse(output),
            [
                .capsLockToF18,
                KeyMapping(source: 0x7_0000_0064, destination: 0x7_0000_0035),
            ]
        )
    }

    func testCollapsesPerServiceDuplicates() {
        // Real hidutil output lists every HID service, most with the same mapping.
        let output = """
            RegistryID  Key                   Value
            10000093c   UserKeyMapping   (
                    {
                    HIDKeyboardModifierMappingDst = 30064771181;
                    HIDKeyboardModifierMappingSrc = 30064771129;
                }
            )
            1000007c9   UserKeyMapping   (null)
            10000090e   UserKeyMapping   (
                    {
                    HIDKeyboardModifierMappingDst = 30064771181;
                    HIDKeyboardModifierMappingSrc = 30064771129;
                }
            )
            """
        XCTAssertEqual(KeyMappingCodec.parse(output), [.capsLockToF18])
    }

    func testCapsLockConstantsMatchTN2450() {
        XCTAssertEqual(HIDUsage.capsLock, 30_064_771_129)
        XCTAssertEqual(HIDUsage.f18, 30_064_771_181)
    }

    func testEncodeRoundTripsThroughJSON() throws {
        let json = KeyMappingCodec.encode([.capsLockToF18])
        XCTAssertEqual(
            json,
            #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":30064771129,"HIDKeyboardModifierMappingDst":30064771181}]}"#
        )
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        XCTAssertEqual(KeyMappingCodec.encode([]), #"{"UserKeyMapping":[]}"#)
    }

    func testAddingKeepsOtherMappingsAndReplacesSameSource() {
        let sectionKey = KeyMapping(source: 0x7_0000_0064, destination: 0x7_0000_0035)
        let oldCaps = KeyMapping(source: HIDUsage.capsLock, destination: 0x7_0000_0029)
        let merged = KeyMappingCodec.adding(.capsLockToF18, to: [sectionKey, oldCaps])
        XCTAssertEqual(merged, [sectionKey, .capsLockToF18])
    }

    func testRemovingOnlyRemovesOurExactMapping() {
        let sectionKey = KeyMapping(source: 0x7_0000_0064, destination: 0x7_0000_0035)
        XCTAssertEqual(KeyMappingCodec.removing(.capsLockToF18, from: [sectionKey, .capsLockToF18]), [sectionKey])
        let someoneElses = KeyMapping(source: HIDUsage.capsLock, destination: 0x7_0000_0029)
        XCTAssertEqual(KeyMappingCodec.removing(.capsLockToF18, from: [someoneElses]), [someoneElses])
    }
}
