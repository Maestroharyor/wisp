import XCTest

@testable import WispCore

final class ThemeTests: XCTestCase {
    func testParsesHexWithOrWithoutHash() {
        XCTAssertEqual(RGB(hex: "#7A6BFF"), RGB(red: 122 / 255, green: 107 / 255, blue: 1))
        XCTAssertEqual(RGB(hex: "7a6bff"), RGB(red: 122 / 255, green: 107 / 255, blue: 1))
        XCTAssertEqual(RGB(hex: " #000000 "), RGB(red: 0, green: 0, blue: 0))
    }

    func testRejectsMalformedHex() {
        XCTAssertNil(RGB(hex: "#7A6BF"))
        XCTAssertNil(RGB(hex: "#GGGGGG"))
        XCTAssertNil(RGB(hex: ""))
    }

    func testHexRoundTrips() {
        XCTAssertEqual(RGB(hex: "#2EC4B6")?.hex, "#2EC4B6")
    }

    func testVioletIsTheDefaultAndMatchesTheBrand() {
        XCTAssertEqual(ThemeID.default, .violet)
        let violet = ThemeCatalog.palette(for: .violet, custom: .init(accent: .white, glow: .white))
        XCTAssertEqual(violet.accent.hex, "#7A6BFF")
        XCTAssertEqual(violet.glow.hex, "#7A6BFF")
    }

    func testAuroraIsAGradient() {
        let aurora = ThemeCatalog.palette(for: .aurora, custom: .init(accent: .white, glow: .white))
        XCTAssertNotEqual(aurora.accent, aurora.glow)
    }

    func testCustomUsesTheUsersColours() {
        let custom = ThemePalette(accent: RGB(red: 1, green: 0, blue: 0), glow: RGB(red: 0, green: 0, blue: 1))
        XCTAssertEqual(ThemeCatalog.palette(for: .custom, custom: custom), custom)
    }

    func testEveryThemeHasATitle() {
        for id in ThemeID.allCases { XCTAssertFalse(ThemeCatalog.title(for: id).isEmpty) }
    }

    func testLiftsDarkSamplesSoTheGlowStaysVisible() {
        let dark = RGB(red: 0.05, green: 0.02, blue: 0.1)
        let lifted = dark.liftedForGlow()
        XCTAssertGreaterThanOrEqual(max(lifted.red, lifted.green, lifted.blue), 0.7)
        // The hue survives: blue stays the strongest channel.
        XCTAssertEqual(max(lifted.red, lifted.green, lifted.blue), lifted.blue)
    }
}
