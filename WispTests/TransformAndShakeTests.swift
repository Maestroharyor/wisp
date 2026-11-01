import CoreGraphics
import XCTest

@testable import WispCore

final class TransformAndShakeTests: XCTestCase {
    // MARK: Shake

    private func feed(_ detector: inout ShakeDetector, _ xs: [CGFloat], step: TimeInterval = 0.05) -> Bool {
        var shaken = false
        for (index, x) in xs.enumerated() {
            shaken = detector.add(CGPoint(x: x, y: 300), at: TimeInterval(index) * step) || shaken
        }
        return shaken
    }

    func testQuickSideToSideIsAShake() {
        var detector = ShakeDetector()
        XCTAssertTrue(feed(&detector, [0, 60, 0, 60, 0, 60]))
    }

    func testSmallJitterIsNotAShake() {
        var detector = ShakeDetector()
        XCTAssertFalse(feed(&detector, [0, 8, 0, 8, 0, 8, 0]))
    }

    func testSlowSweepIsNotAShake() {
        var detector = ShakeDetector()
        XCTAssertFalse(feed(&detector, [0, 80, 0, 80, 0, 80], step: 0.4))
    }

    func testStraightDragIsNotAShake() {
        var detector = ShakeDetector()
        XCTAssertFalse(feed(&detector, [0, 40, 80, 120, 160, 200]))
    }

    func testFiresOnceUntilReset() {
        var detector = ShakeDetector()
        XCTAssertTrue(feed(&detector, [0, 60, 0, 60, 0, 60]))
        XCTAssertFalse(detector.add(CGPoint(x: 0, y: 300), at: 0.31))
        detector.reset()
        XCTAssertTrue(feed(&detector, [0, 60, 0, 60, 0, 60]))
    }

    // MARK: Transform naming and estimates

    func testOutputNameChangesExtensionAndAvoidsClashes() {
        let source = URL(fileURLWithPath: "/tmp/Photo.HEIC")
        XCTAssertEqual(
            TransformNaming.output(for: source, suffix: nil, ext: "jpg", existing: []).lastPathComponent, "Photo.jpg")
        XCTAssertEqual(
            TransformNaming.output(for: source, suffix: "small", ext: "jpg", existing: ["Photo small.jpg"])
                .lastPathComponent,
            "Photo small 2.jpg")
        XCTAssertEqual(
            TransformNaming.output(for: source, suffix: nil, ext: "heic", existing: []).lastPathComponent,
            "Photo converted.heic", "never overwrite the original")
    }

    func testOutputNameAvoidsFilesDifferingOnlyInCase() {
        let source = URL(fileURLWithPath: "/tmp/IMG_0001.HEIC")
        XCTAssertEqual(
            TransformNaming.output(for: source, suffix: nil, ext: "jpg", existing: ["IMG_0001.HEIC", "IMG_0001.JPG"])
                .lastPathComponent,
            "IMG_0001 2.jpg")
        let decomposed = "Cafe\u{301}.png"
        XCTAssertEqual(
            TransformNaming.output(
                for: URL(fileURLWithPath: "/tmp/Café.heic"), suffix: nil, ext: "png", existing: [decomposed]
            ).lastPathComponent,
            "Café 2.png")
    }

    func testRenamePattern() {
        let date = Date(timeIntervalSince1970: 1_761_696_000)  // 2025-10-29 UTC
        XCTAssertEqual(
            TransformNaming.rename(pattern: "Trip {n}", original: "IMG_1", index: 3, date: date, timeZone: .gmt),
            "Trip 3")
        XCTAssertEqual(
            TransformNaming.rename(pattern: "{date}-{name}", original: "IMG_1", index: 1, date: date, timeZone: .gmt),
            "2025-10-29-IMG_1")
    }

    func testResizeFitsLongestSide() {
        XCTAssertEqual(
            TransformMath.fit(CGSize(width: 4000, height: 3000), longestSide: 2048), CGSize(width: 2048, height: 1536))
        XCTAssertEqual(
            TransformMath.fit(CGSize(width: 800, height: 600), longestSide: 2048), CGSize(width: 800, height: 600))
    }

    func testSizeEstimateText() {
        XCTAssertEqual(
            TransformMath.savingsText(before: 5_100_000, after: 1_300_000), "5.1 MB → 1.3 MB · 75% smaller")
        XCTAssertEqual(TransformMath.savingsText(before: 1_000_000, after: 1_200_000), "1 MB → 1.2 MB · 20% larger")
        XCTAssertEqual(TransformMath.savingsText(before: 0, after: 10), "")
    }
}
