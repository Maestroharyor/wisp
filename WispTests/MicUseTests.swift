import XCTest

@testable import WispCore

final class MicUseTests: XCTestCase {
    func testCallAppsAreCalls() {
        XCTAssertEqual(MicUse.classify(inputBundleIDs: ["us.zoom.xos"], meetingInProgress: false), .call)
        XCTAssertEqual(MicUse.classify(inputBundleIDs: ["com.apple.FaceTime"], meetingInProgress: false), .call)
    }

    func testOtherAppsAreRecordings() {
        XCTAssertEqual(MicUse.classify(inputBundleIDs: ["com.apple.VoiceMemos"], meetingInProgress: false), .recording)
    }

    func testBrowsersAreCallsOnlyDuringAMeeting() {
        XCTAssertEqual(MicUse.classify(inputBundleIDs: ["com.google.Chrome"], meetingInProgress: false), .recording)
        XCTAssertEqual(MicUse.classify(inputBundleIDs: ["com.google.Chrome"], meetingInProgress: true), .call)
    }

    func testACallAppWinsOverARecorder() {
        let ids = ["com.apple.VoiceMemos", "com.microsoft.teams2"]
        XCTAssertEqual(MicUse.classify(inputBundleIDs: ids, meetingInProgress: false), .call)
    }

    func testUnknownAppsFollowTheCalendar() {
        XCTAssertEqual(MicUse.classify(inputBundleIDs: [], meetingInProgress: false), .recording)
        XCTAssertEqual(MicUse.classify(inputBundleIDs: [], meetingInProgress: true), .call)
        XCTAssertEqual(MicUse.classify(inputBundleIDs: ["com.apple.VoiceMemos"], meetingInProgress: true), .call)
    }
}
