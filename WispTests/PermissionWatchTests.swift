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

    func testBringsForwardOnlySoonAfterAnAllow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let asked = PermissionRequest(id: "camera", at: now.addingTimeInterval(-60))
        XCTAssertTrue(PermissionWatch.shouldBringForward(newlyGranted: ["camera"], request: asked, now: now))
        XCTAssertFalse(PermissionWatch.shouldBringForward(newlyGranted: [], request: asked, now: now))
    }

    func testOnlyThePermissionAskedForCounts() {
        let now = Date(timeIntervalSince1970: 1_000)
        let asked = PermissionRequest(id: "camera", at: now.addingTimeInterval(-60))
        XCTAssertFalse(PermissionWatch.shouldBringForward(newlyGranted: ["automation"], request: asked, now: now))
        XCTAssertTrue(
            PermissionWatch.shouldBringForward(newlyGranted: ["automation", "camera"], request: asked, now: now))
    }

    func testNoAllowOrAnOldOneDoesNotBringForward() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(PermissionWatch.shouldBringForward(newlyGranted: ["camera"], request: nil, now: now))
        let old = PermissionRequest(id: "camera", at: now.addingTimeInterval(-(PermissionWatch.requestWindow + 1)))
        XCTAssertFalse(PermissionWatch.shouldBringForward(newlyGranted: ["camera"], request: old, now: now))
    }
}
