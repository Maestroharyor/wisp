import Foundation
import XCTest

@testable import WispCore

final class InstanceGuardTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    func testAloneItStays() {
        XCTAssertFalse(InstanceGuard.yields(InstanceGuard.Instance(pid: 10, launched: now), to: []))
    }

    func testTheNewerCopyYields() {
        let older = InstanceGuard.Instance(pid: 20, launched: now.addingTimeInterval(-60))
        let newer = InstanceGuard.Instance(pid: 10, launched: now)
        XCTAssertTrue(InstanceGuard.yields(newer, to: [older]))
        XCTAssertFalse(InstanceGuard.yields(older, to: [newer]))
    }

    func testCopiesLaunchedTogetherKeepTheLowerProcess() {
        // Exactly one of two simultaneous launches stays.
        let first = InstanceGuard.Instance(pid: 10, launched: now)
        let second = InstanceGuard.Instance(pid: 11, launched: now)
        XCTAssertFalse(InstanceGuard.yields(first, to: [second]))
        XCTAssertTrue(InstanceGuard.yields(second, to: [first]))
    }

    func testAnUnknownLaunchTimeCountsAsOlder() {
        let unknown = InstanceGuard.Instance(pid: 30, launched: nil)
        let me = InstanceGuard.Instance(pid: 10, launched: now)
        XCTAssertTrue(InstanceGuard.yields(me, to: [unknown]))
    }

    func testItselfInTheListIsIgnored() {
        let me = InstanceGuard.Instance(pid: 10, launched: now)
        XCTAssertFalse(InstanceGuard.yields(me, to: [me]))
    }
}
