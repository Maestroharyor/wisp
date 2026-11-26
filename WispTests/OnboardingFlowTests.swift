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
}
