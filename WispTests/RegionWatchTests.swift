import CoreGraphics
import XCTest

@testable import WispCore

final class RegionWatchTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func frame(_ value: UInt8, changed: Int = 0, side: Int = 10) -> LuminanceFrame {
        var pixels = [UInt8](repeating: value, count: side * side)
        for index in 0..<min(changed, pixels.count) { pixels[index] = value &+ 100 }
        guard let frame = LuminanceFrame(width: side, height: side, pixels: pixels) else {
            preconditionFailure("bad test frame")
        }
        return frame
    }

    private func sample(_ frame: LuminanceFrame, text: String? = nil, at seconds: TimeInterval) -> RegionWatchSample {
        RegionWatchSample(frame: frame, text: text, time: start.addingTimeInterval(seconds))
    }

    // MARK: Frames

    func testFrameRejectsWrongPixelCount() {
        XCTAssertNil(LuminanceFrame(width: 4, height: 4, pixels: [0, 1, 2]))
        XCTAssertNil(LuminanceFrame(width: 0, height: 4, pixels: []))
    }

    func testCountsPixelsPastTheTolerance() {
        XCTAssertEqual(frame(50).changedPixels(from: frame(50)), 0)
        XCTAssertEqual(frame(50, changed: 10).changedPixels(from: frame(50)), 10)
    }

    func testSmallNoiseIsIgnored() {
        XCTAssertEqual(frame(60).changedPixels(from: frame(50)), 0)
    }

    func testDifferentSizesCountAsChanged() {
        XCTAssertTrue(frame(50, side: 10).isChanged(from: frame(50, side: 8)))
    }

    func testAFewPixelsAreNotAChange() {
        XCTAssertFalse(frame(50, changed: 5).isChanged(from: frame(50)))
        XCTAssertTrue(frame(50, changed: 6).isChanged(from: frame(50)))
    }

    func testOneDigitChangingInAWideStatusLineIsAChange() {
        // A 600 x 20 pt status line keeps its shape: 480 x 16 pixels.
        let size = LuminanceFrame.gridSize(for: CGSize(width: 600, height: 20))
        XCTAssertEqual(size, CGSize(width: 480, height: 16))
        let width = Int(size.width)
        let height = Int(size.height)
        let blank = [UInt8](repeating: 30, count: width * height)
        var digit = blank
        // One glyph about 8 x 11 px changes a dozen of its pixels ("3" to "8").
        for row in 3..<9 {
            for column in [300, 307] { digit[row * width + column] = 220 }
        }
        guard let before = LuminanceFrame(width: width, height: height, pixels: blank),
            let after = LuminanceFrame(width: width, height: height, pixels: digit)
        else { return XCTFail("bad frames") }
        XCTAssertEqual(after.changedPixels(from: before), 12)
        XCTAssertTrue(after.isChanged(from: before))
    }

    func testABigRegionNeedsMoreThanAFewPixels() {
        guard let blank = LuminanceFrame(width: 128, height: 128, pixels: [UInt8](repeating: 30, count: 128 * 128))
        else { return XCTFail("bad frame") }
        var pixels = blank.pixels
        for index in 0..<12 { pixels[index] = 220 }
        guard let speck = LuminanceFrame(width: 128, height: 128, pixels: pixels) else { return XCTFail("bad frame") }
        XCTAssertFalse(speck.isChanged(from: blank))
    }

    func testGridKeepsTheRegionShapeWithinBudget() {
        XCTAssertEqual(LuminanceFrame.gridSize(for: CGSize(width: 1000, height: 1000)), CGSize(width: 128, height: 128))
        XCTAssertEqual(LuminanceFrame.gridSize(for: CGSize(width: 2000, height: 400)), CGSize(width: 128, height: 26))
        XCTAssertEqual(LuminanceFrame.gridSize(for: CGSize(width: 50, height: 30)), CGSize(width: 50, height: 30))
        let thin = LuminanceFrame.gridSize(for: CGSize(width: 4000, height: 30))
        XCTAssertLessThanOrEqual(thin.width * thin.height, CGFloat(LuminanceFrame.pixelBudget))
        XCTAssertGreaterThanOrEqual(thin.height, 1)
    }

    // MARK: Rules

    func testOnlyTheTextRuleNeedsOCR() {
        XCTAssertFalse(RegionWatchRule.changed.needsText)
        XCTAssertTrue(RegionWatchRule.containsText("done").needsText)
        XCTAssertFalse(RegionWatchRule.stoppedChanging(seconds: 10).needsText)
    }

    func testTextMatchIgnoresCaseAccentsAndLineBreaks() {
        let rule = RegionWatchRule.containsText("Build succeeded")
        XCTAssertTrue(rule.matches(text: "** BUILD\nSUCCEEDED **"))
        XCTAssertTrue(RegionWatchRule.containsText("cafe").matches(text: "Café open"))
        XCTAssertFalse(rule.matches(text: "Build failed"))
        XCTAssertFalse(RegionWatchRule.containsText("  ").matches(text: "anything"))
    }

    func testSummaries() {
        XCTAssertEqual(RegionWatchRule.changed.summary, "Any change")
        XCTAssertEqual(RegionWatchRule.containsText("done").summary, "Shows “done”")
        XCTAssertEqual(RegionWatchRule.stoppedChanging(seconds: 10).summary, "Still for 10 s")
        XCTAssertEqual(RegionWatchRule.changed.firedText, "Changed")
        XCTAssertEqual(RegionWatchRule.containsText("done").firedText, "Shows “done”")
        XCTAssertEqual(RegionWatchRule.stoppedChanging(seconds: 10).firedText, "Stopped changing")
    }

    // MARK: Monitor

    func testChangedFiresAfterTwoChangedFrames() {
        var monitor = RegionWatchMonitor(rule: .changed)
        XCTAssertEqual(monitor.observe(sample(frame(50), at: 0)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 30), at: 3)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 30), at: 6)), .fired)
    }

    func testChangedIgnoresAOneFrameFlicker() {
        var monitor = RegionWatchMonitor(rule: .changed)
        _ = monitor.observe(sample(frame(50), at: 0))
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 30), at: 3)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50), at: 6)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 30), at: 9)), .watching)
    }

    func testChangedComparesWithTheFirstFrameSoSlowChangesAddUp() {
        var monitor = RegionWatchMonitor(rule: .changed)
        _ = monitor.observe(sample(frame(50), at: 0))
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 1), at: 3)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 7), at: 6)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 9), at: 9)), .fired)
    }

    func testTextFiresAfterTwoMatchingReads() {
        var monitor = RegionWatchMonitor(rule: .containsText("done"))
        XCTAssertEqual(monitor.observe(sample(frame(50), text: "Working", at: 0)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50), text: "Done", at: 4)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50), text: nil, at: 8)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50), text: "All done", at: 12)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50), text: "DONE", at: 16)), .fired)
    }

    func testStoppedChangingWaitsForAChangeFirst() {
        var monitor = RegionWatchMonitor(rule: .stoppedChanging(seconds: 6))
        for second in stride(from: 0.0, through: 30, by: 3) {
            XCTAssertEqual(monitor.observe(sample(frame(50), at: second)), .watching)
        }
    }

    func testStoppedChangingFiresOnceStillForLongEnough() {
        var monitor = RegionWatchMonitor(rule: .stoppedChanging(seconds: 6))
        _ = monitor.observe(sample(frame(50), at: 0))
        XCTAssertEqual(monitor.observe(sample(frame(90), at: 2)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(130), at: 4)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(130), at: 6)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(130), at: 8)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(130), at: 10)), .fired)
    }

    func testStoppedChangingRestartsOnEveryChange() {
        var monitor = RegionWatchMonitor(rule: .stoppedChanging(seconds: 6))
        _ = monitor.observe(sample(frame(50), at: 0))
        _ = monitor.observe(sample(frame(90), at: 2))
        _ = monitor.observe(sample(frame(90), at: 6))
        XCTAssertEqual(monitor.observe(sample(frame(130), at: 7)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(130), at: 12)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(130), at: 13)), .fired)
    }

    func testResumingAfterAPauseRestartsTheStillnessClock() {
        var monitor = RegionWatchMonitor(rule: .stoppedChanging(seconds: 6))
        _ = monitor.observe(sample(frame(50), at: 0))
        _ = monitor.observe(sample(frame(90), at: 2))
        monitor.resume(at: start.addingTimeInterval(60))
        XCTAssertEqual(monitor.observe(sample(frame(90), at: 62)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(90), at: 66)), .fired)
    }

    func testResumingDropsAHalfConfirmedChange() {
        var monitor = RegionWatchMonitor(rule: .changed)
        _ = monitor.observe(sample(frame(50), at: 0))
        _ = monitor.observe(sample(frame(50, changed: 30), at: 3))
        monitor.resume(at: start.addingTimeInterval(60))
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 30), at: 63)), .watching)
        XCTAssertEqual(monitor.observe(sample(frame(50, changed: 30), at: 66)), .fired)
    }

    // MARK: Blinking cursor

    /// A 40 x 20 frame: optionally a 10 x 10 block of real content changed, and a 3 x 3
    /// cursor-sized square on or off.
    private func screen(contentChanged: Bool = false, cursor: Bool) -> LuminanceFrame {
        let width = 40
        var pixels = [UInt8](repeating: 30, count: width * 20)
        if contentChanged {
            for row in 0..<10 { for column in 0..<10 { pixels[row * width + column] = 200 } }
        }
        if cursor {
            for row in 12..<15 { for column in 30..<33 { pixels[row * width + column] = 220 } }
        }
        guard let frame = LuminanceFrame(width: width, height: 20, pixels: pixels) else {
            preconditionFailure("bad test frame")
        }
        return frame
    }

    func testABlinkingCursorDoesNotFireChanged() {
        var monitor = RegionWatchMonitor(rule: .changed)
        for step in 0..<10 {
            let outcome = monitor.observe(sample(screen(cursor: step % 2 == 1), at: Double(step) * 3))
            XCTAssertEqual(outcome, .watching, "step \(step)")
        }
    }

    func testABlinkingCursorStillLetsRealChangesFire() {
        var monitor = RegionWatchMonitor(rule: .changed)
        for step in 0..<4 { _ = monitor.observe(sample(screen(cursor: step % 2 == 1), at: Double(step) * 3)) }
        XCTAssertEqual(monitor.observe(sample(screen(contentChanged: true, cursor: false), at: 12)), .watching)
        XCTAssertEqual(monitor.observe(sample(screen(contentChanged: true, cursor: true), at: 15)), .fired)
    }

    func testABlinkingCursorDoesNotBlockStoppedChanging() {
        var monitor = RegionWatchMonitor(rule: .stoppedChanging(seconds: 6))
        _ = monitor.observe(sample(screen(cursor: false), at: 0))
        XCTAssertEqual(monitor.observe(sample(screen(contentChanged: true, cursor: true), at: 2)), .watching)
        XCTAssertEqual(monitor.observe(sample(screen(contentChanged: true, cursor: false), at: 4)), .watching)
        XCTAssertEqual(monitor.observe(sample(screen(contentChanged: true, cursor: true), at: 6)), .watching)
        XCTAssertEqual(monitor.observe(sample(screen(contentChanged: true, cursor: false), at: 8)), .fired)
    }

    func testOneDigitChangeInAStatusLineFiresChanged() {
        let width = 480
        let blank = [UInt8](repeating: 30, count: width * 16)
        var digit = blank
        for row in 3..<9 { for column in [300, 307] { digit[row * width + column] = 220 } }
        guard let before = LuminanceFrame(width: width, height: 16, pixels: blank),
            let after = LuminanceFrame(width: width, height: 16, pixels: digit)
        else { return XCTFail("bad frames") }
        var monitor = RegionWatchMonitor(rule: .changed)
        XCTAssertEqual(monitor.observe(sample(before, at: 0)), .watching)
        XCTAssertEqual(monitor.observe(sample(after, at: 3)), .watching)
        XCTAssertEqual(monitor.observe(sample(after, at: 6)), .fired)
    }

    // MARK: Flicker mask bounds

    private func flips(_ indices: [Int], of count: Int) -> [Bool] {
        var flipped = [Bool](repeating: false, count: count)
        for index in indices { flipped[index] = true }
        return flipped
    }

    func testMaskNeedsTwoFlips() {
        var mask = FlickerMask()
        XCTAssertFalse(mask.record(flips([3], of: 800), pixelCount: 800))
        XCTAssertFalse(mask.mask[3])
        XCTAssertFalse(mask.record(flips([3], of: 800), pixelCount: 800))
        XCTAssertTrue(mask.mask[3])
    }

    func testMaskForgetsAPixelThatStopsFlipping() {
        var mask = FlickerMask()
        _ = mask.record(flips([3], of: 800), pixelCount: 800)
        _ = mask.record(flips([3], of: 800), pixelCount: 800)
        for _ in 0..<FlickerMask.memory { _ = mask.record(nil, pixelCount: 800) }
        XCTAssertTrue(mask.mask[3])
        _ = mask.record(nil, pixelCount: 800)
        XCTAssertFalse(mask.mask[3])
        _ = mask.record(flips([3], of: 800), pixelCount: 800)
        XCTAssertFalse(mask.mask[3], "needs two fresh flips")
    }

    func testTooMuchFlickerIsARealChangeAndClearsTheMask() {
        var mask = FlickerMask()
        let small = Array(0..<16)
        _ = mask.record(flips(small, of: 800), pixelCount: 800)
        XCTAssertFalse(mask.record(flips(small, of: 800), pixelCount: 800), "2% is allowed")
        let big = Array(0..<17)
        _ = mask.record(flips(big, of: 800), pixelCount: 800)
        XCTAssertTrue(mask.record(flips(big, of: 800), pixelCount: 800))
        XCTAssertFalse(mask.mask.contains(true))
    }

    func testNeededPixelsCountOnlyUnmaskedOnes() {
        let count = 100 * 100
        guard let before = LuminanceFrame(width: 100, height: 100, pixels: [UInt8](repeating: 30, count: count))
        else { return XCTFail("bad frame") }
        var pixels = before.pixels
        for index in 9_000..<9_007 { pixels[index] = 220 }
        guard let after = LuminanceFrame(width: 100, height: 100, pixels: pixels) else { return XCTFail("bad frame") }
        XCTAssertFalse(after.isChanged(from: before), "7 of 10,000 is a speck")
        let mask = (0..<count).map { $0 < 9_000 }
        XCTAssertTrue(after.isChanged(from: before, ignoring: mask), "7 of the 1,000 left is a change")
    }

    /// A 40 x 20 log of random dark and light pixels that scrolls up one row a frame.
    private struct ScrollingLog {
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        var rows: [[UInt8]] = []

        mutating func nextRow() -> [UInt8] {
            (0..<40).map { _ in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return (seed >> 33) % 3 == 0 ? 220 : 30
            }
        }

        mutating func scroll() -> LuminanceFrame {
            if rows.isEmpty { rows = (0..<20).map { _ in nextRow() } }
            rows.removeFirst()
            rows.append(nextRow())
            guard let frame = LuminanceFrame(width: 40, height: 20, pixels: rows.flatMap { $0 }) else {
                preconditionFailure("bad test frame")
            }
            return frame
        }
    }

    func testStoppedChangingWaitsForAScrollingLogToStop() {
        var log = ScrollingLog()
        var monitor = RegionWatchMonitor(rule: .stoppedChanging(seconds: 6))
        var last = log.scroll()
        for step in 0..<40 {
            last = log.scroll()
            XCTAssertEqual(monitor.observe(sample(last, at: Double(step) * 2)), .watching, "step \(step)")
        }
        XCTAssertEqual(monitor.observe(sample(last, at: 80)), .watching)
        XCTAssertEqual(monitor.observe(sample(last, at: 82)), .watching)
        XCTAssertEqual(monitor.observe(sample(last, at: 84)), .fired)
    }

    // MARK: Small regions

    /// A 200 x 20 pt prompt line drawn at 160 x 16 (1.25 pt a pixel), with an 8 x 17 pt
    /// cursor (6 x 14 px, about 3% of the frame) and optionally some real content changed.
    private func promptLine(contentChanged: Bool = false, cursor: Bool, at seconds: TimeInterval)
        -> RegionWatchSample
    {
        let width = 160
        var pixels = [UInt8](repeating: 30, count: width * 16)
        if contentChanged {
            for row in 0..<10 { for column in 0..<10 { pixels[row * width + column] = 200 } }
        }
        if cursor {
            for row in 1..<15 { for column in 100..<106 { pixels[row * width + column] = 220 } }
        }
        guard let frame = LuminanceFrame(width: width, height: 16, pixels: pixels) else {
            preconditionFailure("bad test frame")
        }
        return RegionWatchSample(
            frame: frame, text: nil, time: start.addingTimeInterval(seconds), pointsPerPixel: 1.25)
    }

    func testCursorFloorIsOneCursorAtTheGridScale() {
        XCTAssertEqual(FlickerMask.cursorFloor(pointsPerPixel: 1.25), 128)
        XCTAssertEqual(FlickerMask.cursorFloor(pointsPerPixel: 1), 200)
    }

    func testACursorInASmallRegionDoesNotFireChanged() {
        var monitor = RegionWatchMonitor(rule: .changed)
        for step in 0..<10 {
            let outcome = monitor.observe(promptLine(cursor: step % 2 == 1, at: Double(step) * 3))
            XCTAssertEqual(outcome, .watching, "step \(step)")
        }
    }

    func testACursorInASmallRegionDoesNotBlockStoppedChanging() {
        var monitor = RegionWatchMonitor(rule: .stoppedChanging(seconds: 6))
        _ = monitor.observe(promptLine(cursor: false, at: 0))
        XCTAssertEqual(monitor.observe(promptLine(contentChanged: true, cursor: true, at: 2)), .watching)
        XCTAssertEqual(monitor.observe(promptLine(contentChanged: true, cursor: false, at: 4)), .watching)
        XCTAssertEqual(monitor.observe(promptLine(contentChanged: true, cursor: true, at: 6)), .watching)
        XCTAssertEqual(monitor.observe(promptLine(contentChanged: true, cursor: false, at: 8)), .fired)
    }

    func testFlickerMarksOnlyPixelsThatFlipBack() {
        let mask = LuminanceFrame.flickering(
            older: screen(cursor: false), previous: screen(contentChanged: true, cursor: true),
            current: screen(contentChanged: true, cursor: false))
        XCTAssertEqual(mask?.filter { $0 }.count, 9)
    }

    func testFiredStaysFired() {
        var monitor = RegionWatchMonitor(rule: .changed)
        _ = monitor.observe(sample(frame(50), at: 0))
        _ = monitor.observe(sample(frame(50, changed: 30), at: 3))
        _ = monitor.observe(sample(frame(50, changed: 30), at: 6))
        XCTAssertEqual(monitor.observe(sample(frame(50), at: 9)), .fired)
    }

    // MARK: Schedule

    func testIntervalsStayBetweenTwoAndFiveSeconds() {
        XCTAssertEqual(RegionWatchSchedule.interval(for: .changed), 3)
        XCTAssertEqual(RegionWatchSchedule.interval(for: .containsText("x")), 4)
        XCTAssertEqual(RegionWatchSchedule.interval(for: .stoppedChanging(seconds: 3)), 2)
        XCTAssertEqual(RegionWatchSchedule.interval(for: .stoppedChanging(seconds: 9)), 3)
        XCTAssertEqual(RegionWatchSchedule.interval(for: .stoppedChanging(seconds: 600)), 5)
    }

    func testPausesOnLowBatteryUnlessCharging() {
        XCTAssertTrue(
            RegionWatchSchedule.isPaused(battery: BatteryState(percent: 19, isPluggedIn: false, isCharging: false)))
        XCTAssertFalse(
            RegionWatchSchedule.isPaused(battery: BatteryState(percent: 20, isPluggedIn: false, isCharging: false)))
        XCTAssertFalse(
            RegionWatchSchedule.isPaused(battery: BatteryState(percent: 10, isPluggedIn: true, isCharging: true)))
        XCTAssertFalse(
            RegionWatchSchedule.isPaused(battery: BatteryState(percent: 10, isPluggedIn: true, isCharging: false)))
        XCTAssertFalse(RegionWatchSchedule.isPaused(battery: nil))
    }

    func testNextStep() {
        let low = BatteryState(percent: 5, isPluggedIn: false, isCharging: false)
        XCTAssertEqual(RegionWatchSchedule.next(for: .changed, battery: nil), .capture(after: 3))
        XCTAssertEqual(
            RegionWatchSchedule.next(for: .changed, battery: low), .paused(checkAfter: RegionWatchSchedule.pausedCheck))
    }

    // MARK: Geometry

    func testFlipsAppKitRectsToTopLeftOrigin() {
        let flipped = RegionGeometry.flipped(CGRect(x: 10, y: 700, width: 100, height: 50), primaryHeight: 1000)
        XCTAssertEqual(flipped, CGRect(x: 10, y: 250, width: 100, height: 50))
    }

    func testRegionIsAnOffsetInPointsFromTheWindowCorner() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 200)
        let region = RegionGeometry.region(CGRect(x: 200, y: 150, width: 100, height: 50), in: window)
        XCTAssertEqual(region, CGRect(x: 100, y: 50, width: 100, height: 50))
    }

    func testSelectionIsClippedToTheWindow() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 200)
        let region = RegionGeometry.region(CGRect(x: 0, y: 0, width: 300, height: 200), in: window)
        XCTAssertEqual(region, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    func testTinySelectionsAreRefused() {
        let window = CGRect(x: 0, y: 0, width: 400, height: 200)
        XCTAssertNil(RegionGeometry.region(CGRect(x: 10, y: 10, width: 4, height: 40), in: window))
        XCTAssertNil(RegionGeometry.region(CGRect(x: 500, y: 10, width: 40, height: 40), in: window))
    }

    func testSourceRectFollowsAResizedWindow() {
        let region = CGRect(x: 100, y: 50, width: 100, height: 50)
        XCTAssertEqual(RegionGeometry.sourceRect(region, windowSize: CGSize(width: 800, height: 600)), region)
        XCTAssertEqual(
            RegionGeometry.sourceRect(region, windowSize: CGSize(width: 150, height: 600)),
            CGRect(x: 100, y: 50, width: 50, height: 50))
        XCTAssertNil(RegionGeometry.sourceRect(region, windowSize: CGSize(width: 90, height: 600)))
    }

    func testTextCaptureUsesTheDisplayScaleButIsCapped() {
        XCTAssertEqual(
            RegionGeometry.textCaptureSize(for: CGSize(width: 300, height: 40), scale: 2),
            CGSize(width: 600, height: 80))
        XCTAssertEqual(
            RegionGeometry.textCaptureSize(for: CGSize(width: 3000, height: 1500), scale: 2),
            CGSize(width: 4000, height: 2000))
    }

    // MARK: Stop button

    func testStopZoneOnlyWhereTheButtonIsDrawn() {
        let pill = CGRect(x: 0, y: 0, width: 300, height: 32)
        XCTAssertEqual(
            SurfaceSizing.pillButtonZone(in: pill, placement: .top, minimal: false),
            CGRect(x: 300 - SurfaceSizing.meetingMuteWidth, y: 0, width: SurfaceSizing.meetingMuteWidth, height: 32))
        XCTAssertNil(SurfaceSizing.pillButtonZone(in: pill, placement: .top, minimal: true))
        XCTAssertNil(SurfaceSizing.pillButtonZone(in: pill, placement: .left, minimal: false))
    }

    func testPicksTheFrontmostNormalWindowUnderThePoint() {
        let windows = [
            WindowCandidate(id: 1, layer: 25, frame: CGRect(x: 0, y: 0, width: 2000, height: 30), ownerPID: 9),
            WindowCandidate(id: 2, layer: 0, frame: CGRect(x: 0, y: 0, width: 2000, height: 2000), ownerPID: 42),
            WindowCandidate(id: 3, layer: 0, frame: CGRect(x: 0, y: 0, width: 500, height: 500), ownerPID: 7),
            WindowCandidate(id: 4, layer: 0, frame: CGRect(x: 0, y: 0, width: 900, height: 900), ownerPID: 8),
        ]
        XCTAssertEqual(RegionGeometry.topWindow(at: CGPoint(x: 10, y: 10), in: windows, excluding: 42)?.id, 3)
        XCTAssertEqual(RegionGeometry.topWindow(at: CGPoint(x: 700, y: 700), in: windows, excluding: 42)?.id, 4)
        XCTAssertNil(RegionGeometry.topWindow(at: CGPoint(x: 1500, y: 1500), in: windows, excluding: 42))
    }
}
