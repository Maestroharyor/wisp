import XCTest

@testable import WispCore

final class MicStateTests: XCTestCase {
    func testPlaybackThroughAHeadsetIsNotRecording() {
        XCTAssertFalse(MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: []))
    }

    func testAProcessWithInputRunningIsInUse() {
        XCTAssertTrue(
            MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: ["com.apple.VoiceMemos"]))
    }

    func testNoInputDeviceIsNeverInUse() {
        XCTAssertFalse(MicState.inUse(hasInputDevice: false, deviceRunning: true, inputProcesses: ["us.zoom.xos"]))
        XCTAssertFalse(MicState.inUse(hasInputDevice: false, deviceRunning: true, inputProcesses: nil))
    }

    func testUnreadableProcessListFallsBackToTheDeviceFlag() {
        XCTAssertTrue(MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: nil))
        XCTAssertFalse(MicState.inUse(hasInputDevice: true, deviceRunning: false, inputProcesses: nil))
    }

    func testTheSiriListenerIsNotRecording() {
        XCTAssertFalse(
            MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: ["com.apple.CoreSpeech"]))
        XCTAssertTrue(
            MicState.inUse(
                hasInputDevice: true, deviceRunning: true, inputProcesses: ["com.apple.CoreSpeech", "us.zoom.xos"]))
    }

    func testAProcessWithoutABundleIDStillCounts() {
        XCTAssertTrue(MicState.inUse(hasInputDevice: true, deviceRunning: false, inputProcesses: [""]))
    }

    func testNamedAppsLeaveOutListenersAndUnnamedProcesses() {
        XCTAssertEqual(MicState.apps(["us.zoom.xos", "", "com.apple.CoreSpeech"]), ["us.zoom.xos"])
    }
}
