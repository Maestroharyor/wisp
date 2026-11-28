import XCTest

@testable import WispCore

final class ShellCornersTests: XCTestCase {
    private func corners(_ spec: SurfaceSpec, notch: Bool, floating: Bool = false) -> ShellCorners {
        ShellMetrics.corners(
            for: spec, drawsNotch: notch, floating: floating, peekHeight: 40, notchHeight: 32, roundness: 1)
    }

    func testTheClosedNotchFlaresIntoTheMenuBarAndMatchesTheHousing() {
        let closed = corners(.closed, notch: true)
        XCTAssertEqual(closed.flare, ShellMetrics.closedTopRadius(height: 32))
        XCTAssertEqual(closed.topCorner, 0)
        XCTAssertEqual(closed.bottom, ShellMetrics.closedBottomRadius(height: 32))
        XCTAssertEqual(closed.island, 0)
    }

    func testAnIslandHasNoFlareAndTheSameRoundingAllRound() {
        let island = corners(.compact(wide: false), notch: false)
        XCTAssertEqual(island.flare, 0)
        XCTAssertEqual(island.topCorner, island.bottom)
        XCTAssertEqual(island.bottom, ShellMetrics.closedIslandRadius)
        XCTAssertEqual(island.island, 1)
    }

    func testTheClosedOrbIsRound() {
        XCTAssertEqual(corners(.closed, notch: false, floating: true).bottom, 20)
    }

    func testTheOpenShelfUsesTheShelfRounding() {
        let shelf = corners(.media, notch: true)
        XCTAssertEqual(shelf.flare, ShellMetrics.expandedTopRadius)
        XCTAssertEqual(shelf.bottom, ShellMetrics.expandedShelfBottomRadius)
        XCTAssertEqual(corners(.media, notch: false, floating: true).bottom, ShellMetrics.floatingShelfRadius)
    }

    func testRoundnessScalesEverythingButTheClosedNotch() {
        let round = ShellMetrics.corners(
            for: .media, drawsNotch: true, floating: false, peekHeight: 40, notchHeight: 32, roundness: 0.5)
        XCTAssertEqual(round.bottom, ShellMetrics.expandedShelfBottomRadius * 0.5)
        let closed = ShellMetrics.corners(
            for: .closed, drawsNotch: true, floating: false, peekHeight: 40, notchHeight: 32, roundness: 0.5)
        XCTAssertEqual(closed.bottom, ShellMetrics.closedBottomRadius(height: 32))
    }

    /// A form change goes from a notch to an island through every value in between.
    func testBlendingMovesEveryCornerPartWay() {
        let notch = corners(.closed, notch: true)
        let island = corners(.closed, notch: false)
        let half = ShellCorners.blend(notch, island, progress: 0.5)
        XCTAssertEqual(half.flare, notch.flare / 2, accuracy: 1e-9)
        XCTAssertEqual(half.topCorner, island.topCorner / 2, accuracy: 1e-9)
        XCTAssertEqual(half.bottom, (notch.bottom + island.bottom) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.island, 0.5, accuracy: 1e-9)
        XCTAssertEqual(ShellCorners.blend(notch, island, progress: 0), notch)
        XCTAssertEqual(ShellCorners.blend(notch, island, progress: 1), island)
    }

    /// Notch flares and an island's convex top corners never both show: the top corner's
    /// signed size runs from flaring out (negative) to rounding in (positive).
    func testTheTopCornerIsOneSignedSize() {
        XCTAssertEqual(ShellCorners(flare: 8, topCorner: 0, bottom: 12, island: 0).signedTop, -8)
        XCTAssertEqual(ShellCorners(flare: 0, topCorner: 20, bottom: 20, island: 1).signedTop, 20)
        XCTAssertEqual(ShellCorners(flare: 4, topCorner: 10, bottom: 16, island: 0.5).signedTop, 6)
    }
}
