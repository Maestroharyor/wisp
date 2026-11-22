import XCTest

@testable import WispCore

final class WindowArtTests: XCTestCase {
    func testRidgesAreTheSameForTheSameSeed() {
        XCTAssertEqual(
            NightRidge.layers(seed: 7, hour: 22, isDark: true), NightRidge.layers(seed: 7, hour: 22, isDark: true))
        XCTAssertNotEqual(
            NightRidge.layers(seed: 7, hour: 22, isDark: true).first?.heights,
            NightRidge.layers(seed: 8, hour: 22, isDark: true).first?.heights)
    }

    func testRidgesStepDownTowardTheViewerAndStayInFrame() {
        let layers = NightRidge.layers(seed: 3, hour: 21, isDark: true)
        XCTAssertEqual(layers.count, NightRidge.layerCount)
        let means = layers.map { $0.heights.reduce(0, +) / Double($0.heights.count) }
        XCTAssertEqual(means, means.sorted(by: >))
        for layer in layers {
            XCTAssertEqual(layer.heights.count, NightRidge.samples)
            XCTAssertTrue(layer.heights.allSatisfy { (0.05...0.95).contains($0) })
        }
    }

    func testNearerRidgesAreDarker() {
        for isDark in [true, false] {
            let layers = NightRidge.layers(seed: 1, hour: 14, isDark: isDark)
            let light = layers.map(\.colour.luminance)
            XCTAssertEqual(light, light.sorted(by: >))
        }
    }

    func testStarsAreStableAndInTheUpperSky() {
        let stars = NightRidge.stars(seed: 4, count: 30)
        XCTAssertEqual(stars, NightRidge.stars(seed: 4, count: 30))
        XCTAssertEqual(stars.count, 30)
        XCTAssertTrue(stars.allSatisfy { (0...1).contains($0.x) && (0...0.6).contains($0.y) && $0.size > 0 })
    }

    func testStarsShowInDarkModeOrAtNight() {
        XCTAssertTrue(NightRidge.showsStars(hour: 12, isDark: true))
        XCTAssertTrue(NightRidge.showsStars(hour: 23, isDark: false))
        XCTAssertFalse(NightRidge.showsStars(hour: 12, isDark: false))
    }

    func testTheDailyLineHoldsForADayAndChangesTheNext() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let morning = Date(timeIntervalSince1970: 1_700_000_000)
        let start = calendar.startOfDay(for: morning)
        XCTAssertEqual(
            WindowTaglines.line(for: start, calendar: calendar),
            WindowTaglines.line(for: start.addingTimeInterval(86_399), calendar: calendar))
        let week = (0..<7).map {
            WindowTaglines.line(for: start.addingTimeInterval(Double($0) * 86_400), calendar: calendar)
        }
        XCTAssertEqual(Set(week).count, 7)
    }

    func testEveryLineIsShortAndHasNoEmDash() {
        for line in WindowTaglines.lines + WindowTaglines.phrases.values.map({ $0 }) {
            XCTAssertLessThanOrEqual(line.count, 44, line)
            XCTAssertFalse(line.contains("\u{2014}"), line)
        }
        XCTAssertGreaterThanOrEqual(WindowTaglines.lines.count, 20)
    }

    func testEveryPageAndWidgetHasAPhrase() {
        let widgets = [
            "nowPlaying", "calendar", "reminders", "timer", "pomodoro", "battery", "systemStats", "weather", "notes",
            "quickToggles", "shortcuts", "clipboard", "mirror", "dayProgress", "worldClocks", "agents", "script",
            "quickInput",
        ]
        for page in WindowPage.allCases {
            XCTAssertNotEqual(WindowTaglines.phrase(for: .page(page)), WindowTaglines.fallback)
        }
        for id in widgets {
            XCTAssertNotEqual(WindowTaglines.phrase(for: .widget(id)), WindowTaglines.fallback, id)
        }
        XCTAssertEqual(WindowTaglines.phrase(for: .widget("unknown")), WindowTaglines.fallback)
        XCTAssertEqual(WindowTaglines.phrase(for: .live(.downloads)), WindowTaglines.fallback)
    }
}
