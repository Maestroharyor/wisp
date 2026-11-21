import XCTest

@testable import WispCore

final class PageKeysTests: XCTestCase {
    func testLeftAndRightStepThroughPages() {
        XCTAssertEqual(PageKeys.step(PageKeys.left), -1)
        XCTAssertEqual(PageKeys.step(PageKeys.right), 1)
        XCTAssertNil(PageKeys.step(KeyCodes.space))
    }

    func testStepsStopAtTheEndsRatherThanWrapping() {
        XCTAssertEqual(PageKeys.next(from: 0, step: 1, count: 4), 1)
        XCTAssertEqual(PageKeys.next(from: 3, step: 1, count: 4), 3)
        XCTAssertEqual(PageKeys.next(from: 0, step: -1, count: 4), 0)
        XCTAssertEqual(PageKeys.next(from: 2, step: -1, count: 4), 1)
    }
}
