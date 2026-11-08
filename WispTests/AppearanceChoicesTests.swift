import XCTest

@testable import WispCore

final class AccentSourceTests: XCTestCase {
    private func look(wallpaper: Bool, album: Bool) -> Appearance {
        var look = Appearance()
        look.wallpaperTint = wallpaper
        look.adaptiveAccent = album
        return look
    }

    func testReadsEveryStoredCombination() {
        XCTAssertEqual(look(wallpaper: false, album: false).accentSource, .theme)
        XCTAssertEqual(look(wallpaper: true, album: false).accentSource, .wallpaper)
        XCTAssertEqual(look(wallpaper: false, album: true).accentSource, .album)
        XCTAssertEqual(look(wallpaper: true, album: true).accentSource, .album)
    }

    func testAlbumFallsBackToTheThemeOrToTheDesktopPictureWhenBothWereOn() {
        XCTAssertEqual(look(wallpaper: false, album: true).albumFallback, .theme)
        XCTAssertEqual(look(wallpaper: true, album: true).albumFallback, .wallpaper)
    }

    func testPickingThemeOrDesktopPictureSetsBothSwitches() {
        for start in [(false, false), (true, false), (false, true), (true, true)] {
            var theme = look(wallpaper: start.0, album: start.1)
            theme.accentSource = .theme
            XCTAssertFalse(theme.wallpaperTint)
            XCTAssertFalse(theme.adaptiveAccent)

            var wallpaper = look(wallpaper: start.0, album: start.1)
            wallpaper.accentSource = .wallpaper
            XCTAssertTrue(wallpaper.wallpaperTint)
            XCTAssertFalse(wallpaper.adaptiveAccent)
        }
    }

    func testPickingAlbumFromAnotherSourceFallsBackToTheTheme() {
        var fromWallpaper = look(wallpaper: true, album: false)
        fromWallpaper.accentSource = .album
        XCTAssertEqual(fromWallpaper, look(wallpaper: false, album: true))

        var fromTheme = look(wallpaper: false, album: false)
        fromTheme.accentSource = .album
        XCTAssertEqual(fromTheme, look(wallpaper: false, album: true))
    }

    func testPickingAlbumAgainKeepsAnOlderDesktopPictureFallback() {
        var both = look(wallpaper: true, album: true)
        both.accentSource = .album
        XCTAssertEqual(both, look(wallpaper: true, album: true))
    }

    func testEverySourceReadsBackAsPicked() {
        for source in AccentSource.allCases {
            var look = Appearance()
            look.accentSource = source
            XCTAssertEqual(look.accentSource, source)
        }
    }

    func testTitles() {
        XCTAssertEqual(AccentSource.allCases.map(\.title), ["Theme", "Desktop picture", "Playing album"])
    }
}

final class ConfettiSwitchTests: XCTestCase {
    private func look(pomodoro: Bool, agent: Bool, battery: Bool) -> Appearance {
        var look = Appearance()
        look.confettiPomodoro = pomodoro
        look.confettiAgent = agent
        look.confettiBattery = battery
        return look
    }

    func testOffByDefault() {
        XCTAssertFalse(Appearance().confetti)
        XCTAssertFalse(Appearance().confettiIsPartial)
    }

    func testOnWhenAnyMomentIsOn() {
        XCTAssertTrue(look(pomodoro: true, agent: false, battery: false).confetti)
        XCTAssertTrue(look(pomodoro: false, agent: true, battery: false).confetti)
        XCTAssertTrue(look(pomodoro: false, agent: false, battery: true).confetti)
        XCTAssertTrue(look(pomodoro: true, agent: true, battery: true).confetti)
    }

    func testPartialOnlyWhenSomeButNotAllAreOn() {
        XCTAssertTrue(look(pomodoro: true, agent: false, battery: true).confettiIsPartial)
        XCTAssertFalse(look(pomodoro: true, agent: true, battery: true).confettiIsPartial)
        XCTAssertFalse(look(pomodoro: false, agent: false, battery: false).confettiIsPartial)
    }

    func testSwitchWritesAllThree() {
        var on = look(pomodoro: false, agent: true, battery: false)
        on.confetti = true
        XCTAssertEqual(on, look(pomodoro: true, agent: true, battery: true))

        var off = look(pomodoro: true, agent: false, battery: true)
        off.confetti = false
        XCTAssertEqual(off, look(pomodoro: false, agent: false, battery: false))
    }
}
