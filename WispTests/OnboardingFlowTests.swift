import XCTest

@testable import WispCore

final class OnboardingFlowTests: XCTestCase {
    func testStepsRunInOrder() {
        XCTAssertEqual(OnboardingStep.allCases, [.accessibility, .opening, .agents])
        XCTAssertEqual(OnboardingStep.accessibility.next, .opening)
        XCTAssertEqual(OnboardingStep.opening.next, .agents)
        XCTAssertNil(OnboardingStep.agents.next)
        XCTAssertNil(OnboardingStep.accessibility.previous)
        XCTAssertEqual(OnboardingStep.agents.previous, .opening)
    }

    func testOnlyAccessibilityWaitsForTheGrant() {
        XCTAssertEqual(OnboardingStep.accessibility.primaryAction(accessibilityGranted: false), "Skip for Now")
        XCTAssertEqual(OnboardingStep.accessibility.primaryAction(accessibilityGranted: true), "Continue")
        XCTAssertEqual(OnboardingStep.opening.primaryAction(accessibilityGranted: false), "Continue")
        XCTAssertEqual(OnboardingStep.agents.primaryAction(accessibilityGranted: true), "Done")
    }

    func testExistingInstallsSkipSetup() {
        XCTAssertTrue(OnboardingStep.needsSetup(storedFlag: nil, hasEarlierSettings: false))
        XCTAssertFalse(OnboardingStep.needsSetup(storedFlag: nil, hasEarlierSettings: true))
        XCTAssertFalse(OnboardingStep.needsSetup(storedFlag: true, hasEarlierSettings: false))
        XCTAssertTrue(OnboardingStep.needsSetup(storedFlag: false, hasEarlierSettings: true))
    }
}
