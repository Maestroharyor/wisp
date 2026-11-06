import XCTest

@testable import WispCore

final class MicStateTests: XCTestCase {
    func testPlaybackThroughAHeadsetIsNotRecording() {
        XCTAssertFalse(MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: 0))
    }

    func testAProcessWithInputRunningIsInUse() {
        XCTAssertTrue(MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: 1))
    }

    func testNoInputDeviceIsNeverInUse() {
        XCTAssertFalse(MicState.inUse(hasInputDevice: false, deviceRunning: true, inputProcesses: 2))
        XCTAssertFalse(MicState.inUse(hasInputDevice: false, deviceRunning: true, inputProcesses: nil))
    }

    func testUnreadableProcessListFallsBackToTheDeviceFlag() {
        XCTAssertTrue(MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: nil))
        XCTAssertFalse(MicState.inUse(hasInputDevice: true, deviceRunning: false, inputProcesses: nil))
    }
}
