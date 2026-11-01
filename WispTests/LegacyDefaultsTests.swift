import XCTest

@testable import WispCore

final class LegacyDefaultsTests: XCTestCase {
    func testCopiesWispKeys() {
        XCTAssertTrue(LegacyDefaults.shouldCopy(key: "appearance"))
        XCTAssertTrue(LegacyDefaults.shouldCopy(key: "placement"))
        XCTAssertTrue(LegacyDefaults.shouldCopy(key: "lookPresets"))
    }

    func testSkipsSystemWindowState() {
        XCTAssertFalse(LegacyDefaults.shouldCopy(key: "NSWindow Frame Settings"))
        XCTAssertFalse(LegacyDefaults.shouldCopy(key: "NSNavLastRootDirectory"))
        XCTAssertFalse(LegacyDefaults.shouldCopy(key: "AppleLanguages"))
        XCTAssertFalse(LegacyDefaults.shouldCopy(key: "com.apple.something"))
    }

    func testSkipsTheImportFlag() {
        XCTAssertFalse(LegacyDefaults.shouldCopy(key: LegacyDefaults.importedFlagKey))
    }

    func testEntriesKeepOnlyCopyableKeys() {
        let old = ["appearance": 1, "NSWindow Frame Settings": 2, "onboarded": 3]
        XCTAssertEqual(LegacyDefaults.entriesToCopy(from: old), ["appearance": 1, "onboarded": 3])
    }

    func testDomainsDiffer() {
        XCTAssertEqual(LegacyDefaults.oldDomain, "com.maestro.wisp")
        XCTAssertNotEqual(LegacyDefaults.oldDomain, "com.ayomideodewale.wisp")
    }
}
