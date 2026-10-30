import XCTest

@testable import WispCore

final class SpringTuningTests: XCTestCase {
    func testRefreshTiers() {
        XCTAssertEqual(SpringTuning.refreshScale(framesPerSecond: 120), 1)
        XCTAssertEqual(SpringTuning.refreshScale(framesPerSecond: 100), 1)
        XCTAssertEqual(SpringTuning.refreshScale(framesPerSecond: 90), 1.1)
        XCTAssertEqual(SpringTuning.refreshScale(framesPerSecond: 75), 1.1)
        XCTAssertEqual(SpringTuning.refreshScale(framesPerSecond: 60), 1.18)
        XCTAssertEqual(SpringTuning.refreshScale(framesPerSecond: 0), 1.18)
    }

    func testOpenAtProMotionUsesBaseValues() {
        let spec = SpringTuning.surface(opening: true, speedScale: 1, framesPerSecond: 120, reduceMotion: false)
        XCTAssertEqual(spec, SpringTuning.surfaceOpen)
    }

    func testCloseAtSixtyHertzStretchesResponse() {
        let spec = SpringTuning.surface(opening: false, speedScale: 1, framesPerSecond: 60, reduceMotion: false)
        XCTAssertEqual(spec.response, 0.54 * 1.18, accuracy: 1e-9)
        XCTAssertEqual(spec.dampingFraction, 0.9)
    }

    func testCloseSettlesWithLessOvershootThanOpen() {
        XCTAssertGreaterThan(SpringTuning.surfaceClose.dampingFraction, SpringTuning.surfaceOpen.dampingFraction)
    }

    func testReduceMotionIsCriticallyDampedAndIgnoresSpeed() {
        let spec = SpringTuning.surface(opening: true, speedScale: 2, framesPerSecond: 120, reduceMotion: true)
        XCTAssertEqual(spec, SpringTuning.reducedMotion)
    }

    func testPhysicalForm() {
        let spec = SpringSpec(response: 0.5, dampingFraction: 1)
        XCTAssertEqual(spec.stiffness, pow(4 * .pi, 2), accuracy: 1e-9)
        XCTAssertEqual(spec.damping, 8 * .pi, accuracy: 1e-9)
    }
}
