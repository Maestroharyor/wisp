import CoreGraphics
import XCTest

@testable import WispCore

final class SpringTuningTests: XCTestCase {
    func testGrowingUsesTheOpenSpring() {
        let spec = SpringTuning.surface(move: .grow, speedScale: 1, reduceMotion: false)
        XCTAssertEqual(spec, SpringTuning.surfaceOpen)
    }

    func testShrinkingUsesTheCloseSpring() {
        let spec = SpringTuning.surface(move: .shrink, speedScale: 1, reduceMotion: false)
        XCTAssertEqual(spec, SpringTuning.surfaceClose)
    }

    func testClosingIsNoSlowerThanOpening() {
        XCTAssertLessThanOrEqual(SpringTuning.surfaceClose.response, SpringTuning.surfaceOpen.response)
    }

    func testClosingNeverOvershoots() {
        XCTAssertGreaterThanOrEqual(SpringTuning.surfaceClose.dampingFraction, 1)
    }

    func testOpeningHasOnlyASmallBounce() {
        XCTAssertGreaterThanOrEqual(SpringTuning.surfaceOpen.dampingFraction, 0.78)
        XCTAssertLessThan(SpringTuning.surfaceOpen.dampingFraction, 0.9)
    }

    func testSpeedScalesResponseOnly() {
        let spec = SpringTuning.surface(move: .grow, speedScale: 1.2, reduceMotion: false)
        XCTAssertEqual(spec.response, SpringTuning.surfaceOpen.response * 1.2, accuracy: 1e-9)
        XCTAssertEqual(spec.dampingFraction, SpringTuning.surfaceOpen.dampingFraction)
    }

    func testReduceMotionIsCriticallyDampedAndIgnoresSpeed() {
        for move in [SurfaceMove.grow, .shrink] {
            let spec = SpringTuning.surface(move: move, speedScale: 2, reduceMotion: true)
            XCTAssertEqual(spec, SpringTuning.reducedMotion)
        }
    }

    func testContentSpringsDontOvershoot() {
        XCTAssertGreaterThanOrEqual(SpringTuning.contentIn.dampingFraction, 1)
        XCTAssertGreaterThanOrEqual(SpringTuning.contentOut.dampingFraction, 1)
        XCTAssertLessThan(SpringTuning.contentOut.response, SpringTuning.contentIn.response)
    }

    func testPhysicalForm() {
        let spec = SpringSpec(response: 0.5, dampingFraction: 1)
        XCTAssertEqual(spec.stiffness, pow(4 * .pi, 2), accuracy: 1e-9)
        XCTAssertEqual(spec.damping, 8 * .pi, accuracy: 1e-9)
    }
}

final class SurfaceMoveTests: XCTestCase {
    func testCollapsingToALivePillShrinks() {
        let shelf = CGSize(width: 640, height: 300)
        let pill = CGSize(width: 320, height: 37)
        XCTAssertEqual(SurfaceMove.between(shelf, pill), .shrink)
    }

    func testExpandingFromAPillToACardGrows() {
        XCTAssertEqual(SurfaceMove.between(CGSize(width: 320, height: 37), CGSize(width: 480, height: 110)), .grow)
    }

    func testAWiderButShorterShapeGoesByArea() {
        XCTAssertEqual(SurfaceMove.between(CGSize(width: 200, height: 200), CGSize(width: 400, height: 50)), .shrink)
    }

    func testTheSameSizeSettlesWithoutABounce() {
        let size = CGSize(width: 640, height: 300)
        XCTAssertEqual(SurfaceMove.between(size, size), .shrink)
    }
}

final class SpringSolverTests: XCTestCase {
    private func solver(_ response: Double, _ damping: Double, velocity: Double = 0) -> SpringSolver {
        SpringSolver(SpringSpec(response: response, dampingFraction: damping), initialVelocity: velocity)
    }

    func testStartsAtZeroAndSettlesAtOne() {
        for damping in [0.6, 1, 1.4] {
            let spring = solver(0.4, damping)
            XCTAssertEqual(spring.value(at: 0), 0, accuracy: 1e-9)
            XCTAssertEqual(spring.value(at: 5), 1, accuracy: 1e-4, "damping \(damping)")
        }
    }

    func testCriticalDampingNeverOvershoots() {
        let spring = solver(0.4, 1)
        for step in 0...400 {
            XCTAssertLessThanOrEqual(spring.value(at: Double(step) / 200), 1 + 1e-9)
        }
    }

    func testUnderdampingOvershoots() {
        let spring = solver(0.4, 0.6)
        let peak = (0...400).map { spring.value(at: Double($0) / 200) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.05)
    }

    func testInitialVelocityCarriesForward() {
        let still = solver(0.4, 1)
        let thrown = solver(0.4, 1, velocity: 8)
        XCTAssertGreaterThan(thrown.value(at: 0.05), still.value(at: 0.05))
        XCTAssertEqual(thrown.velocity(at: 0), 8, accuracy: 1e-9)
    }

    func testVelocityMatchesTheSlopeOfValue() {
        for damping in [0.7, 1, 1.3] {
            let spring = solver(0.5, damping, velocity: 2)
            let t = 0.12
            let slope = (spring.value(at: t + 1e-5) - spring.value(at: t - 1e-5)) / 2e-5
            XCTAssertEqual(spring.velocity(at: t), slope, accuracy: 1e-3, "damping \(damping)")
        }
    }

    func testAQuickerResponseSettlesSooner() {
        XCTAssertLessThan(solver(0.3, 1).settleTime(), solver(0.6, 1).settleTime())
        XCTAssertGreaterThan(solver(0.3, 1).settleTime(), 0)
    }
}

final class InteractivePullTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 500)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testRubberBandFollowsCloselyAtFirst() {
        XCTAssertEqual(RubberBand.offset(0, limit: 100), 0)
        XCTAssertEqual(RubberBand.offset(1, limit: 100), 0.55, accuracy: 0.01)
    }

    func testRubberBandNeverPassesItsLimit() {
        XCTAssertLessThan(RubberBand.offset(10_000, limit: 100), 100)
        XCTAssertGreaterThan(RubberBand.offset(-10_000, limit: 100), -100)
        XCTAssertEqual(RubberBand.offset(-40, limit: 100), -RubberBand.offset(40, limit: 100), accuracy: 1e-9)
    }

    func testVelocityFromEvenSamples() {
        var tracker = VelocityTracker()
        for step in 0...5 { tracker.add(Double(step) * 10, at: at(Double(step) * 0.01)) }
        XCTAssertEqual(tracker.velocity(now: at(0.05)), 1_000, accuracy: 1e-6)
    }

    func testAPauseBeforeLettingGoMeansNoThrow() {
        var tracker = VelocityTracker()
        for step in 0...5 { tracker.add(Double(step) * 10, at: at(Double(step) * 0.01)) }
        XCTAssertEqual(tracker.velocity(now: at(0.3)), 0)
    }

    func testOneSampleHasNoVelocity() {
        var tracker = VelocityTracker()
        tracker.add(5, at: at(0))
        XCTAssertEqual(tracker.velocity(now: at(0)), 0)
    }

    func testProjectionMatchesUIKit() {
        XCTAssertEqual(Momentum.project(0, velocity: 1_000), 499, accuracy: 1e-6)
        XCTAssertEqual(Momentum.project(10, velocity: 0), 10)
    }

    func testProgressFollowsThePullAndRubberBandsPastOpen() {
        var pull = PullTracker(travel: 100)
        XCTAssertEqual(pull.add(50, at: at(0)), 0.5, accuracy: 1e-9)
        let over = pull.add(100, at: at(0.1))
        XCTAssertGreaterThan(over, 1)
        XCTAssertLessThan(over, 1.2)
        let under = pull.add(-250, at: at(0.2))
        XCTAssertLessThan(under, 0)
        XCTAssertGreaterThan(under, -0.2)
    }

    func testASlowPullPastHalfwayOpens() {
        var pull = PullTracker(travel: 100)
        _ = pull.add(30, at: at(0))
        _ = pull.add(30, at: at(0.5))
        XCTAssertTrue(pull.release(now: at(1)).opens)
    }

    func testASlowPullShortOfHalfwayCloses() {
        var pull = PullTracker(travel: 100)
        _ = pull.add(40, at: at(0))
        XCTAssertFalse(pull.release(now: at(1)).opens)
    }

    func testAShortFastFlickOpens() {
        var pull = PullTracker(travel: 100)
        for step in 1...4 { _ = pull.add(4, at: at(Double(step) * 0.01)) }
        let release = pull.release(now: at(0.04))
        XCTAssertTrue(release.opens)
        XCTAssertGreaterThan(release.velocity, 0)
    }

    func testFlickingBackCloses() {
        var pull = PullTracker(travel: 100)
        _ = pull.add(70, at: at(0))
        for step in 1...4 { _ = pull.add(-8, at: at(0.5 + Double(step) * 0.01)) }
        XCTAssertFalse(pull.release(now: at(0.54)).opens)
    }

    func testRelativeVelocityIsTheSpeedOverWhatsLeft() {
        XCTAssertEqual(SpringHandoff.relativeVelocity(2, from: 0.5, to: 1), 4, accuracy: 1e-9)
        XCTAssertEqual(SpringHandoff.relativeVelocity(-2, from: 0.5, to: 0), 4, accuracy: 1e-9)
    }

    func testRelativeVelocityIsZeroWhenAlreadyThere() {
        XCTAssertEqual(SpringHandoff.relativeVelocity(3, from: 1, to: 1), 0)
    }
}

final class PullGateTests: XCTestCase {
    func testAmountsFollowTheSwipeDetectorsSigns() {
        XCTAssertEqual(Swipe.down.amount(dx: 0, dy: -5), 5)
        XCTAssertEqual(Swipe.up.amount(dx: 0, dy: -5), -5)
        XCTAssertEqual(Swipe.right.amount(dx: 3, dy: 0), 3)
        XCTAssertEqual(Swipe.left.amount(dx: 3, dy: 0), -3)
    }

    func testSmallMovementsWait() {
        var gate = PullGate(direction: .down)
        XCTAssertEqual(gate.add(dx: 1, dy: -2), .undecided)
    }

    func testMovingTheOpeningWayIsAPull() {
        var gate = PullGate(direction: .down)
        _ = gate.add(dx: 0, dy: -3)
        XCTAssertEqual(gate.add(dx: 1, dy: -4), .pull(7))
    }

    func testSidewaysOrBackwardsIsLeftToSwipes() {
        var sideways = PullGate(direction: .down)
        XCTAssertEqual(sideways.add(dx: 8, dy: -2), .other)
        var backwards = PullGate(direction: .down)
        XCTAssertEqual(backwards.add(dx: 0, dy: 8), .other)
    }

    func testTheGateDecidesOncePerGesture() {
        var gate = PullGate(direction: .down)
        XCTAssertEqual(gate.add(dx: 8, dy: 0), .other)
        XCTAssertEqual(gate.add(dx: 0, dy: -50), .other)
        gate.reset()
        XCTAssertEqual(gate.add(dx: 0, dy: -8), .pull(8))
    }
}
