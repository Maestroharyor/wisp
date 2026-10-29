import XCTest

@testable import WispCore

final class WidgetLogicTests: XCTestCase {
    func testWeatherCodes() {
        XCTAssertEqual(WeatherCode.describe(0, isDay: true).symbol, "sun.max.fill")
        XCTAssertEqual(WeatherCode.describe(0, isDay: false).symbol, "moon.stars.fill")
        XCTAssertEqual(WeatherCode.describe(2, isDay: true).title, "Partly cloudy")
        XCTAssertEqual(WeatherCode.describe(63, isDay: true).symbol, "cloud.rain.fill")
        XCTAssertEqual(WeatherCode.describe(75, isDay: true).title, "Snow")
        XCTAssertEqual(WeatherCode.describe(95, isDay: true).symbol, "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherCode.describe(999, isDay: true).title, "Unknown")
    }

    func testCPUUsageFromTickDeltas() {
        let before = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let after = CPUTicks(user: 160, system: 70, idle: 870, nice: 0)
        // 80 busy of 100 elapsed.
        XCTAssertEqual(CPUTicks.usage(from: before, to: after), 0.8, accuracy: 1e-9)
        XCTAssertEqual(CPUTicks.usage(from: after, to: after), 0)
    }

    func testMemoryFraction() {
        XCTAssertEqual(MemoryUsage(usedBytes: 8, totalBytes: 16).fraction, 0.5)
        XCTAssertEqual(MemoryUsage(usedBytes: 1, totalBytes: 0).fraction, 0)
    }

    func testRelativeAge() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(RelativeAge.short(from: now.addingTimeInterval(-20), to: now), "now")
        XCTAssertEqual(RelativeAge.short(from: now.addingTimeInterval(-125), to: now), "2m")
        XCTAssertEqual(RelativeAge.short(from: now.addingTimeInterval(-7200), to: now), "2h")
        XCTAssertEqual(RelativeAge.short(from: now.addingTimeInterval(-200_000), to: now), "2d")
    }
}
