import XCTest

@testable import WispCore

final class AppearanceTests: XCTestCase {
    func testDefaultsKeepTodaysLook() {
        let look = Appearance.standard
        XCTAssertEqual(look.theme, .violet)
        XCTAssertEqual(look.surface, .black)
        XCTAssertEqual(look.glassEdge, .subtle)
        XCTAssertEqual(look.roundness, 1)
        XCTAssertEqual(look.opacity, 1)
        XCTAssertEqual(look.shadow, .soft)
        XCTAssertEqual(look.hoverFeedback, .grow)
        XCTAssertEqual(look.outline, .off)
        XCTAssertEqual(look.soundPack, .off)
        XCTAssertFalse(look.pet)
    }

    func testRoundTrip() throws {
        var look = Appearance.standard
        look.theme = .ember
        look.roundness = 1.3
        look.leftEar = .time
        look.customSounds = ["open": "/tmp/a.aiff"]
        let data = try JSONEncoder().encode(look)
        XCTAssertEqual(try JSONDecoder().decode(Appearance.self, from: data), look)
    }

    func testMissingAndUnknownFieldsFallBack() throws {
        let json = Data(#"{"theme":"aurora","surface":"plaid","future":true}"#.utf8)
        let look = try JSONDecoder().decode(Appearance.self, from: json)
        XCTAssertEqual(look.theme, .aurora)
        XCTAssertEqual(look.surface, .black)
        XCTAssertEqual(look.roundness, 1)
    }

    func testNumbersAreClamped() throws {
        let json = Data(#"{"roundness":9,"opacity":0.1,"glowIntensity":-3,"earText":"abcdefghijklmnopq"}"#.utf8)
        let look = try JSONDecoder().decode(Appearance.self, from: json)
        XCTAssertEqual(look.roundness, 1.5)
        XCTAssertEqual(look.opacity, 0.7)
        XCTAssertEqual(look.glowIntensity, 0)
        XCTAssertEqual(look.earText.count, Appearance.earTextLimit)
    }

    func testMigrationCarriesOldSettings() {
        let legacy = LegacyLook(
            theme: "custom", customAccent: "#112233", customGlow: "#445566", wallpaperTint: true,
            adaptiveAccent: true, shellOutline: true, animationSpeed: "fast", surface: "glass", glassEdge: "strong")
        let look = Appearance.migrated(from: legacy)
        XCTAssertEqual(look.theme, .custom)
        XCTAssertEqual(look.customAccent.hex, "#112233")
        XCTAssertEqual(look.customGlow.hex, "#445566")
        XCTAssertTrue(look.wallpaperTint)
        XCTAssertTrue(look.adaptiveAccent)
        XCTAssertEqual(look.outline, .thin)
        XCTAssertEqual(look.animationSpeed, .fast)
        XCTAssertEqual(look.surface, .glass)
        XCTAssertEqual(look.glassEdge, .strong)
    }

    func testMigrationOfAFreshInstallIsTheDefault() {
        XCTAssertEqual(Appearance.migrated(from: LegacyLook()), .standard)
    }

    func testPresetsAreDistinctAndNamed() {
        let names = AppearancePreset.builtIns.map(\.name)
        XCTAssertEqual(names, ["Default", "Calm", "Arcade", "Minimal", "Neon"])
        let looks = AppearancePreset.builtIns.map(\.appearance)
        for (index, look) in looks.enumerated() {
            XCTAssertFalse(looks[(index + 1)...].contains(look), "\(names[index]) repeats another preset")
        }
        XCTAssertEqual(AppearancePreset.builtIns.first?.appearance, .standard)
        for preset in AppearancePreset.builtIns { XCTAssertEqual(preset.appearance, preset.appearance.clamped()) }
    }

    func testUniquePresetNames() {
        XCTAssertEqual(AppearancePreset.uniqueName("Calm", existing: []), "Calm 2")
        XCTAssertEqual(AppearancePreset.uniqueName("Mine", existing: ["Mine", "Mine 2"]), "Mine 3")
        XCTAssertEqual(AppearancePreset.uniqueName("  ", existing: []), "My look")
    }

    func testLookFileRoundTrip() throws {
        var look = Appearance.standard
        look.shimmer = true
        let file = LookFile(name: "Glow", appearance: look)
        XCTAssertEqual(try LookFile.decode(try file.encoded()), file)
    }

    func testLookFileRejectsJunkAndNewerVersions() {
        XCTAssertEqual(readError(Data("nope".utf8)), .notALook)
        XCTAssertEqual(readError(Data(#"{"version":7,"name":"x","appearance":{}}"#.utf8)), .newerVersion(7))
        XCTAssertEqual(readError(Data(#"{"version":0,"name":"x","appearance":{}}"#.utf8)), .notALook)
    }

    func testLookFilesLeaveCustomSoundsBehind() {
        var look = Appearance.standard
        look.soundPack = .custom
        look.customSounds = ["open": "/Users/someone/ding.aiff"]
        let shared = LookFile(name: "Mine", appearance: look).appearance
        XCTAssertTrue(shared.customSounds.isEmpty)
        XCTAssertEqual(shared.soundPack, .off)
        look.soundPack = .soft
        XCTAssertEqual(LookFile(name: "Mine", appearance: look).appearance.soundPack, .soft)
    }

    private func readError(_ data: Data) -> LookFile.ReadError? {
        do {
            _ = try LookFile.decode(data)
            return nil
        } catch {
            return error
        }
    }
}

final class ProfileLookTests: XCTestCase {
    func testOldProfilesDecodeWithoutALook() throws {
        let json = Data(#"{"name":"Work","home":{"slots":[]},"defaultPage":"home","surface":"black"}"#.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertNil(profile.look)
    }

    func testLookRoundTrips() throws {
        let profile = Profile(
            name: "Play", home: HomeLayout(slots: []), defaultPage: "home", surface: "black", look: "Arcade")
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)).look, "Arcade")
    }

    func testPresetsKeepTheUsersCustomSounds() {
        var mine = Appearance()
        mine.customSounds = ["open": "/Sounds/pop.aiff"]
        XCTAssertEqual(Appearance.standard.keepingSounds(of: mine).customSounds, mine.customSounds)

        var saved = Appearance()
        saved.customSounds = ["open": "/Sounds/click.aiff"]
        XCTAssertEqual(saved.keepingSounds(of: mine).customSounds, saved.customSounds)
    }
}
