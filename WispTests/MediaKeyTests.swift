import XCTest

@testable import WispCore

final class MediaKeyTests: XCTestCase {
    /// Builds NX_SYSDEFINED data1: key code in the high 16 bits, state in bits 8-15, repeat in bit 0.
    private func data1(_ code: Int, down: Bool, repeating: Bool = false) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (repeating ? 1 : 0)
    }

    func testDecodesVolumeUpDown() {
        let event = MediaKeyEvent(data1: data1(0, down: true))
        XCTAssertEqual(event?.key, .volumeUp)
        XCTAssertEqual(event?.isDown, true)
        XCTAssertEqual(event?.isRepeat, false)
        XCTAssertEqual(MediaKeyEvent(data1: data1(1, down: false))?.key, .volumeDown)
        XCTAssertEqual(MediaKeyEvent(data1: data1(1, down: false))?.isDown, false)
    }

    func testDecodesMuteBrightnessAndRepeat() {
        XCTAssertEqual(MediaKeyEvent(data1: data1(7, down: true))?.key, .mute)
        XCTAssertEqual(MediaKeyEvent(data1: data1(2, down: true))?.key, .brightnessUp)
        XCTAssertEqual(MediaKeyEvent(data1: data1(3, down: true))?.key, .brightnessDown)
        XCTAssertEqual(MediaKeyEvent(data1: data1(0, down: true, repeating: true))?.isRepeat, true)
    }

    func testIgnoresOtherKeys() {
        XCTAssertNil(MediaKeyEvent(data1: data1(16, down: true)))  // play
    }

    func testStepsSnapToSixteenths() {
        XCTAssertEqual(LevelStep.next(from: 0.5, up: true, fine: false), 0.5625)
        XCTAssertEqual(LevelStep.next(from: 0.5, up: false, fine: false), 0.4375)
        // Off-grid values snap to the next grid point in the pressed direction.
        XCTAssertEqual(LevelStep.next(from: 0.51, up: true, fine: false), 0.5625)
        XCTAssertEqual(LevelStep.next(from: 0.51, up: false, fine: false), 0.5)
    }

    func testFineStepsAndClamping() {
        XCTAssertEqual(LevelStep.next(from: 0.5, up: true, fine: true), 0.515625)
        XCTAssertEqual(LevelStep.next(from: 1, up: true, fine: false), 1)
        XCTAssertEqual(LevelStep.next(from: 0, up: false, fine: false), 0)
    }

    func testPercentLabel() {
        XCTAssertEqual(LevelStep.percent(0.625), 63)
        XCTAssertEqual(LevelStep.percent(1.2), 100)
        XCTAssertEqual(LevelStep.percent(-1), 0)
    }

    func testStepCountSetsTheVolumeGrid() {
        XCTAssertEqual(LevelStep.next(from: 0.5, up: true, steps: 32), 0.5 + 1.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(LevelStep.next(from: 0.5, up: false, steps: 8), 0.375, accuracy: 1e-9)
    }
}
