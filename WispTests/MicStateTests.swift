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

    func testMacOSListenersAndLevelMetersAreNotRecording() {
        for id in [
            "com.apple.Sound-Settings.extension", "com.apple.corespeechd", "com.apple.assistantd", "com.apple.Siri",
            "com.apple.accessibility.heard",
        ] {
            XCTAssertFalse(MicState.inUse(hasInputDevice: true, deviceRunning: true, inputProcesses: [id]), id)
        }
        XCTAssertEqual(MicState.apps(["com.apple.Sound-Settings.extension", "us.zoom.xos"]), ["us.zoom.xos"])
    }

    private let start = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 5_000)

    func testTheTimerStartsWhenTheMicGoesLiveAndStopsWithIt() {
        XCTAssertEqual(
            MicState.since(previous: nil, previousApps: [], apps: ["us.zoom.xos"], inUse: true, now: start), start)
        XCTAssertNil(MicState.since(previous: start, previousApps: ["us.zoom.xos"], apps: [], inUse: false, now: later))
    }

    func testTheTimerKeepsCountingWhileAnyEarlierAppStillHoldsTheMic() {
        let since = MicState.since(
            previous: start, previousApps: ["us.zoom.xos"], apps: ["us.zoom.xos", "com.apple.VoiceMemos"], inUse: true,
            now: later)
        XCTAssertEqual(since, start)
    }

    func testANewAppTakingOverTheMicStartsTheTimerAgain() {
        let since = MicState.since(
            previous: start, previousApps: ["com.apple.VoiceMemos"], apps: ["us.zoom.xos"], inUse: true, now: later)
        XCTAssertEqual(since, later)
    }

    func testUnnamedHoldersKeepTheirStart() {
        XCTAssertEqual(MicState.since(previous: start, previousApps: [], apps: [], inUse: true, now: later), start)
    }
}
