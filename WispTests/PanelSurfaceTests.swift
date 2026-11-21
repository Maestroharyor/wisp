import XCTest

@testable import WispCore

final class PanelSurfaceTests: XCTestCase {
    func testPanelsDefaultToTintedGlassWithNoExtraTint() {
        XCTAssertEqual(Appearance.standard.panelGlass, .tinted)
        XCTAssertEqual(Appearance.standard.panelTint, 0)
    }

    func testAnOldLookWithoutGlassSettingsLoadsTheDefaults() throws {
        let old = Data(#"{"surface":"glass","roundness":1.2}"#.utf8)
        let look = try JSONDecoder().decode(Appearance.self, from: old)
        XCTAssertEqual(look.panelGlass, .tinted)
        XCTAssertEqual(look.panelTint, 0)
        XCTAssertEqual(look.surface, .glass)
    }

    func testGlassSettingsRoundTrip() throws {
        var look = Appearance()
        look.panelGlass = .frosted
        look.panelTint = 0.4
        let decoded = try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(look))
        XCTAssertEqual(decoded.panelGlass, .frosted)
        XCTAssertEqual(decoded.panelTint, 0.4, accuracy: 1e-9)
    }

    func testTintIsClamped() {
        var look = Appearance()
        look.panelTint = 3
        XCTAssertEqual(look.clamped().panelTint, Appearance.panelTintRange.upperBound)
        look.panelTint = -1
        XCTAssertEqual(look.clamped().panelTint, Appearance.panelTintRange.lowerBound)
    }

    func testGlassGetsMoreOpaqueFromClearToFrosted() {
        XCTAssertLessThan(PanelGlass.clear.backing, PanelGlass.tinted.backing)
        XCTAssertLessThan(PanelGlass.tinted.backing, PanelGlass.frosted.backing)
        XCTAssertEqual(PanelGlass.allCases.map(\.title), ["Clear", "Tinted", "Frosted"])
    }

    func testRadiiGrowWithTheSurface() {
        let scale = [
            SurfaceRadius.control, SurfaceRadius.row, SurfaceRadius.card, SurfaceRadius.panel, SurfaceRadius.largePanel,
        ]
        XCTAssertEqual(scale, scale.sorted())
    }

    func testInnerCornersAreConcentric() {
        // Apple's rule: an inner corner is the outer one minus the padding between them.
        XCTAssertEqual(SurfaceRadius.concentric(outer: 26, padding: 16), 10)
        XCTAssertEqual(SurfaceRadius.concentric(outer: 22, padding: 12), 10)
    }

    func testConcentricNeverGoesBelowAControlsCorner() {
        XCTAssertEqual(SurfaceRadius.concentric(outer: 18, padding: 16), SurfaceRadius.minimum)
    }
}
