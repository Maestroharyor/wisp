import XCTest

@testable import WispCore

final class OnboardingFlowTests: XCTestCase {
    func testStepsRunInOrder() {
        XCTAssertEqual(OnboardingStep.allCases, [.accessibility, .opening, .ring, .agents, .finish])
        XCTAssertEqual(OnboardingStep.accessibility.next, .opening)
        XCTAssertEqual(OnboardingStep.opening.next, .ring)
        XCTAssertEqual(OnboardingStep.ring.next, .agents)
        XCTAssertEqual(OnboardingStep.agents.next, .finish)
        XCTAssertNil(OnboardingStep.finish.next)
        XCTAssertNil(OnboardingStep.accessibility.previous)
        XCTAssertEqual(OnboardingStep.finish.previous, .agents)
    }

    func testOnlyAccessibilityWaitsForTheGrant() {
        XCTAssertEqual(OnboardingStep.accessibility.primaryAction(accessibilityGranted: false), "Skip for now")
        XCTAssertEqual(OnboardingStep.accessibility.primaryAction(accessibilityGranted: true), "Continue")
        XCTAssertEqual(OnboardingStep.opening.primaryAction(accessibilityGranted: false), "Continue")
        XCTAssertEqual(OnboardingStep.ring.primaryAction(accessibilityGranted: false), "Continue")
        XCTAssertEqual(OnboardingStep.agents.primaryAction(accessibilityGranted: true), "Continue")
        XCTAssertEqual(OnboardingStep.finish.primaryAction(accessibilityGranted: true), "Done")
    }

    func testExistingInstallsSkipSetup() {
        XCTAssertTrue(OnboardingStep.needsSetup(storedFlag: nil, hasEarlierSettings: false))
        XCTAssertFalse(OnboardingStep.needsSetup(storedFlag: nil, hasEarlierSettings: true))
        XCTAssertFalse(OnboardingStep.needsSetup(storedFlag: true, hasEarlierSettings: false))
        XCTAssertTrue(OnboardingStep.needsSetup(storedFlag: false, hasEarlierSettings: true))
    }

    /// Turning on Screen Recording often means reopening Wisp; setup picks up where it was.
    func testSetupResumesAtTheStepItWasOn() {
        XCTAssertEqual(OnboardingStep.resume(stored: nil), .accessibility)
        XCTAssertEqual(OnboardingStep.resume(stored: OnboardingStep.ring.rawValue), .ring)
        XCTAssertEqual(OnboardingStep.resume(stored: 99), .accessibility)
    }

    func testWindowPreviewsNeedEverythingInTurn() {
        XCTAssertEqual(RingPreviews.need(showsWindows: false, accessibility: true, screenRecording: true), .windowsOff)
        XCTAssertEqual(
            RingPreviews.need(showsWindows: true, accessibility: false, screenRecording: true), .accessibility)
        XCTAssertEqual(
            RingPreviews.need(showsWindows: true, accessibility: true, screenRecording: false), .screenRecording)
        XCTAssertNil(RingPreviews.need(showsWindows: true, accessibility: true, screenRecording: true))
    }
}
