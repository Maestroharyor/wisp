import XCTest

@testable import WispCore

final class SessionLockTests: XCTestCase {
    func testALockIsConfirmedAfterTheWait() {
        var lock = SessionLock()
        XCTAssertEqual(lock.handle(.screenLocked), .confirmLater)
        XCTAssertTrue(lock.confirm(onConsole: true))
        XCTAssertTrue(lock.confirmed)
    }

    func testAUserSwitchIsNotALock() {
        // Fast user switching sends the lock notification, then the session resigns.
        var lock = SessionLock()
        XCTAssertEqual(lock.handle(.screenLocked), .confirmLater)
        XCTAssertEqual(lock.handle(.sessionResigned), .suspend)
        XCTAssertFalse(lock.confirm(onConsole: true))
        XCTAssertFalse(lock.confirmed)
    }

    func testAResignBeforeTheLockSchedulesNothing() {
        var lock = SessionLock()
        XCTAssertEqual(lock.handle(.sessionResigned), .suspend)
        XCTAssertEqual(lock.handle(.screenLocked), .none)
        XCTAssertFalse(lock.confirm(onConsole: true))
    }

    func testASessionOffTheConsoleIsNotALock() {
        var lock = SessionLock()
        _ = lock.handle(.screenLocked)
        XCTAssertFalse(lock.confirm(onConsole: false))
    }

    func testAnUnlockDuringTheWaitCancelsIt() {
        var lock = SessionLock()
        _ = lock.handle(.screenLocked)
        XCTAssertEqual(lock.handle(.screenUnlocked), .unlock)
        XCTAssertFalse(lock.confirm(onConsole: true))
    }

    func testAnUnlockReleasesAConfirmedLock() {
        var lock = SessionLock()
        _ = lock.handle(.screenLocked)
        _ = lock.confirm(onConsole: true)
        XCTAssertEqual(lock.handle(.screenUnlocked), .unlock)
        XCTAssertFalse(lock.confirmed)
    }

    func testALockIsConfirmedOnce() {
        var lock = SessionLock()
        _ = lock.handle(.screenLocked)
        XCTAssertTrue(lock.confirm(onConsole: true))
        XCTAssertFalse(lock.confirm(onConsole: true))
    }

    func testComingBackResumes() {
        var lock = SessionLock()
        _ = lock.handle(.sessionResigned)
        XCTAssertEqual(lock.handle(.sessionResumed), .resume)
        XCTAssertTrue(lock.sessionActive)
    }
}
