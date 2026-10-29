import XCTest

@testable import WispCore

final class ClickSynthTests: XCTestCase {
    func testLengthAndPeak() {
        let samples = ClickSynth.samples(sampleRate: 48_000, major: false)
        XCTAssertEqual(samples.count, Int(48_000 * ClickSynth.duration))
        let peak = samples.map(abs).max() ?? 0
        XCTAssertEqual(peak, ClickSynth.minorPeak, accuracy: 0.001)
    }

    func testMajorIsLouder() {
        let minor = ClickSynth.samples(sampleRate: 48_000, major: false).map(abs).max() ?? 0
        let major = ClickSynth.samples(sampleRate: 48_000, major: true).map(abs).max() ?? 0
        XCTAssertGreaterThan(major, minor)
    }

    func testEnergyIsFrontLoadedAndDiesOut() {
        let samples = ClickSynth.samples(sampleRate: 48_000, major: true)
        let quarter = samples.count / 4
        let early = samples.prefix(quarter).map { $0 * $0 }.reduce(0, +)
        let late = samples.suffix(quarter).map { $0 * $0 }.reduce(0, +)
        XCTAssertGreaterThan(early, late * 100, "a crisp click, not a tone")
        XCTAssertLessThan(abs(samples.last ?? 1), 0.01)
    }

    func testDeterministic() {
        XCTAssertEqual(
            ClickSynth.samples(sampleRate: 44_100, major: false), ClickSynth.samples(sampleRate: 44_100, major: false))
    }
}
