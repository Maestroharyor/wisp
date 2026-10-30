import XCTest

@testable import WispCore

final class BuildNumberTests: XCTestCase {
    func testPacksSemanticVersion() {
        XCTAssertEqual(BuildNumber.from(version: "0.2.0"), 200)
        XCTAssertEqual(BuildNumber.from(version: "0.1.0"), 100)
        XCTAssertEqual(BuildNumber.from(version: "1.0.3"), 10003)
        XCTAssertEqual(BuildNumber.from(version: "2.15.7"), 21507)
    }

    func testGrowsWithEveryRelease() {
        let versions = ["0.1.0", "0.1.1", "0.1.99", "0.2.0", "0.99.0", "1.0.0", "1.0.1"]
        let numbers = versions.compactMap(BuildNumber.from(version:))
        XCTAssertEqual(numbers.count, versions.count)
        XCTAssertEqual(numbers, numbers.sorted())
        XCTAssertEqual(Set(numbers).count, numbers.count)
    }

    func testRejectsMalformedOrOutOfRange() {
        XCTAssertNil(BuildNumber.from(version: "1.0"))
        XCTAssertNil(BuildNumber.from(version: "v1.0.0"))
        XCTAssertNil(BuildNumber.from(version: "1.100.0"))
        XCTAssertNil(BuildNumber.from(version: "1.0.100"))
        XCTAssertNil(BuildNumber.from(version: "1.0.0-beta"))
    }
}
