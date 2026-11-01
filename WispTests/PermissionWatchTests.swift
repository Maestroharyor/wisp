import XCTest

@testable import WispCore

final class PermissionWatchTests: XCTestCase {
    func testAGrantFromNotGrantedCounts() {
        let before: [String: Bool?] = ["camera": false, "contacts": true]
        let after: [String: Bool?] = ["camera": true, "contacts": true]
        XCTAssertEqual(PermissionWatch.newlyGranted(before: before, after: after), ["camera"])
    }

    func testAGrantFromUnknownCounts() {
        let before: [String: Bool?] = ["automation": nil]
        let after: [String: Bool?] = ["automation": true]
        XCTAssertEqual(PermissionWatch.newlyGranted(before: before, after: after), ["automation"])
    }

    func testRevokesAndUnchangedDoNotCount() {
        let before: [String: Bool?] = ["camera": true, "contacts": false]
        let after: [String: Bool?] = ["camera": false, "contacts": false]
        XCTAssertEqual(PermissionWatch.newlyGranted(before: before, after: after), [])
    }

    func testResultIsSorted() {
        let before: [String: Bool?] = ["b": false, "a": false]
        let after: [String: Bool?] = ["b": true, "a": true]
        XCTAssertEqual(PermissionWatch.newlyGranted(before: before, after: after), ["a", "b"])
    }
}
