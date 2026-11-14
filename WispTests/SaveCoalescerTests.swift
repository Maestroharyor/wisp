import XCTest

@testable import WispCore

final class SaveCoalescerTests: XCTestCase {
    func testAChangeWhileIdleStartsASave() {
        var saves = SaveCoalescer()
        XCTAssertTrue(saves.changed())
        XCTAssertTrue(saves.begin())
        XCTAssertTrue(saves.saving)
    }

    func testNothingToSaveDoesNotStart() {
        var saves = SaveCoalescer()
        XCTAssertFalse(saves.begin())
        XCTAssertFalse(saves.saving)
    }

    func testChangesDuringASaveWaitForIt() {
        var saves = SaveCoalescer()
        _ = saves.changed()
        _ = saves.begin()
        XCTAssertFalse(saves.changed())
        XCTAssertFalse(saves.changed())
        XCTAssertFalse(saves.begin())
    }

    func testChangesDuringASaveBecomeOneMoreSave() {
        var saves = SaveCoalescer()
        _ = saves.changed()
        _ = saves.begin()
        _ = saves.changed()
        _ = saves.changed()
        _ = saves.changed()
        XCTAssertTrue(saves.finish())
        XCTAssertTrue(saves.begin())
        XCTAssertFalse(saves.finish())
        XCTAssertFalse(saves.begin())
    }

    func testAQuietSaveEndsTheRun() {
        var saves = SaveCoalescer()
        _ = saves.changed()
        _ = saves.begin()
        XCTAssertFalse(saves.finish())
        XCTAssertFalse(saves.saving)
        XCTAssertTrue(saves.changed())
    }
}
