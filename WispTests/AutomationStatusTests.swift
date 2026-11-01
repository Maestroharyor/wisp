import XCTest

@testable import WispCore

final class AutomationStatusTests: XCTestCase {
    func testAllAllowedIsGranted() {
        XCTAssertEqual(AutomationStatus.summary([0, 0]), true)
    }

    func testADenialIsNotGranted() {
        XCTAssertEqual(AutomationStatus.summary([0, -1743]), false)
    }

    func testNotAskedYetIsNotGranted() {
        XCTAssertEqual(AutomationStatus.summary([-1744, 0]), false)
    }

    func testTargetsThatAreNotRunningAreIgnored() {
        XCTAssertEqual(AutomationStatus.summary([0, -600]), true)
        XCTAssertEqual(AutomationStatus.summary([-1743, -600]), false)
    }

    func testNoAnswerIsUnknown() {
        XCTAssertNil(AutomationStatus.summary([]))
        XCTAssertNil(AutomationStatus.summary([-600, -600]))
    }
}
