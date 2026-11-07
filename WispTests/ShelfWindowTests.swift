import CoreGraphics
import XCTest

@testable import WispCore

final class ShelfWindowStateTests: XCTestCase {
    func testOpenAsWindowFoldsTheShelfAwayAndShowsTheWindow() {
        var state = ShelfWindowState()
        XCTAssertEqual(state.handle(.openAsWindow), [.closeShelves, .showWindow])
        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.windowForm)
        XCTAssertFalse(state.opensUnderShell)
        // Already open: it only comes forward.
        XCTAssertEqual(state.handle(.openAsWindow), [.focusWindow])
    }

    func testPuttingTheWindowAwayGoesBackToTheShell() {
        var state = ShelfWindowState()
        state.handle(.openAsWindow)
        XCTAssertEqual(state.handle(.putAway), [.hideWindow])
        XCTAssertFalse(state.isOpen)
        XCTAssertTrue(state.opensUnderShell)
        XCTAssertEqual(state.form(shell: .orb), .orb)
        // Nothing to put away twice.
        XCTAssertEqual(state.handle(.putAway), [])
    }

    func testAOneOffWindowLeavesTheShellOpeningItsShelfAfterwards() {
        var state = ShelfWindowState()
        state.handle(.openAsWindow)
        XCTAssertEqual(state.handle(.activateShell), [.focusWindow])
        state.handle(.putAway)
        XCTAssertEqual(state.handle(.activateShell), [.openShelf])
    }

    func testTheWindowFormKeepsOpeningTheWindow() {
        var state = ShelfWindowState()
        XCTAssertEqual(state.handle(.pick(.window)), [.closeShelves, .showWindow])
        XCTAssertTrue(state.windowForm)
        XCTAssertEqual(state.form(shell: .notch), .window)
        // Minimising collapses to the shell it had, but the form stays Window.
        XCTAssertEqual(state.handle(.putAway), [.hideWindow])
        XCTAssertTrue(state.windowForm)
        XCTAssertFalse(state.opensUnderShell)
        XCTAssertEqual(state.form(shell: .notch), .window)
        // So the shell brings the window back rather than opening its own shelf.
        XCTAssertEqual(state.handle(.activateShell), [.closeShelves, .showWindow])
        XCTAssertTrue(state.isOpen)
    }

    func testPickingAShellFormLeavesTheWindow() {
        var state = ShelfWindowState(windowForm: true, isOpen: true)
        XCTAssertEqual(state.handle(.pick(.orb)), [.hideWindow, .applyShellForm(.orb)])
        XCTAssertFalse(state.windowForm)
        XCTAssertFalse(state.isOpen)
        XCTAssertEqual(state.form(shell: .orb), .orb)
    }

    func testPickingAShellFormWithNoWindowJustAppliesIt() {
        var state = ShelfWindowState()
        XCTAssertEqual(state.handle(.pick(.corner)), [.applyShellForm(.corner)])
        var minimised = ShelfWindowState(windowForm: true, isOpen: false)
        XCTAssertEqual(minimised.handle(.pick(.notch)), [.applyShellForm(.notch)])
        XCTAssertFalse(minimised.windowForm)
    }

    func testPickingWindowAgainBringsItForward() {
        var state = ShelfWindowState(windowForm: true, isOpen: true)
        XCTAssertEqual(state.handle(.pick(.window)), [.focusWindow])
        var oneOff = ShelfWindowState(windowForm: false, isOpen: true)
        XCTAssertEqual(oneOff.handle(.pick(.window)), [.focusWindow])
        XCTAssertTrue(oneOff.windowForm)
    }

    func testTheShortcutTogglesTheWindowWhenItIsInFront() {
        var state = ShelfWindowState(windowForm: true, isOpen: true)
        XCTAssertEqual(state.handle(.toggle(windowInFront: false)), [.focusWindow])
        XCTAssertEqual(state.handle(.toggle(windowInFront: true)), [.hideWindow])
        XCTAssertEqual(state.handle(.toggle(windowInFront: false)), [.closeShelves, .showWindow])
        var plain = ShelfWindowState()
        XCTAssertEqual(plain.handle(.toggle(windowInFront: false)), [.openShelf])
    }

    func testTurningTheWindowFormOnAndOffInSettings() {
        var state = ShelfWindowState(windowForm: true, isOpen: true)
        XCTAssertEqual(state.handle(.setWindowForm(false)), [.hideWindow])
        XCTAssertFalse(state.windowForm)
        // A one-off window isn't the form's to close.
        var oneOff = ShelfWindowState(windowForm: false, isOpen: true)
        XCTAssertEqual(oneOff.handle(.setWindowForm(false)), [])
        XCTAssertTrue(oneOff.isOpen)
        var off = ShelfWindowState()
        XCTAssertEqual(off.handle(.setWindowForm(true)), [.closeShelves, .showWindow])
        XCTAssertTrue(off.windowForm)
    }
}

final class ShelfWindowFrameTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)

    func testFramesRoundTrip() {
        let frame = CGRect(x: 120, y: -40, width: 760, height: 480)
        XCTAssertEqual(ShelfWindowFrame.decode(ShelfWindowFrame.encode(frame)), frame)
        XCTAssertNil(ShelfWindowFrame.decode("nonsense"))
        XCTAssertNil(ShelfWindowFrame.decode("1,2,3"))
        XCTAssertNil(ShelfWindowFrame.decode("1,2,0,5"))
    }

    func testNoSavedFrameCentresTheDefaultSizeOnTheMainScreen() {
        let frame = ShelfWindowFrame.fitted(nil, screens: [main, right], main: main)
        XCTAssertEqual(frame.size, ShelfWindowFrame.defaultSize)
        XCTAssertEqual(frame.midX, main.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, main.midY, accuracy: 0.5)
    }

    func testASavedFrameOnScreenIsKept() {
        let saved = CGRect(x: 1600, y: 200, width: 800, height: 500)
        XCTAssertEqual(ShelfWindowFrame.fitted(saved, screens: [main, right], main: main), saved)
    }

    func testAFrameHangingOffItsScreenIsPulledBackOn() {
        let saved = CGRect(x: 1200, y: 600, width: 800, height: 500)
        let frame = ShelfWindowFrame.fitted(saved, screens: [main], main: main)
        XCTAssertEqual(frame.size, saved.size)
        XCTAssertTrue(main.contains(frame))
    }

    func testAFrameStraddlingTwoScreensStaysOnTheOneHoldingMostOfIt() {
        let saved = CGRect(x: 1300, y: 100, width: 800, height: 500)
        let frame = ShelfWindowFrame.fitted(saved, screens: [main, right], main: main)
        XCTAssertTrue(right.contains(frame))
    }

    func testAFrameOnAMissingDisplayComesToTheMainScreenAtItsSize() {
        let saved = CGRect(x: 5000, y: 100, width: 800, height: 500)
        let frame = ShelfWindowFrame.fitted(saved, screens: [main], main: main)
        XCTAssertEqual(frame.size, saved.size)
        XCTAssertEqual(frame.midX, main.midX, accuracy: 0.5)
    }

    func testAFrameTooBigForItsScreenShrinksButNotBelowTheMinimum() {
        let small = CGRect(x: 0, y: 0, width: 1024, height: 640)
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertEqual(ShelfWindowFrame.fitted(huge, screens: [small], main: small), small)
        let tiny = ShelfWindowFrame.fitted(CGRect(x: 10, y: 10, width: 100, height: 80), screens: [main], main: main)
        XCTAssertEqual(tiny.size, ShelfWindowFrame.minimumSize)
    }

    func testATornOffWindowHangsFromThePointerByItsTitleBar() {
        let size = CGSize(width: 760, height: 480)
        let frame = ShelfWindowFrame.tornOff(at: CGPoint(x: 700, y: 500), size: size, in: main)
        XCTAssertEqual(frame.size, size)
        XCTAssertEqual(frame.midX, 700, accuracy: 0.5)
        XCTAssertEqual(frame.maxY - 500, ShelfWindowFrame.grabDepth, accuracy: 0.5)
        // Near the top of the screen it's kept on it.
        let high = ShelfWindowFrame.tornOff(at: CGPoint(x: 20, y: 870), size: size, in: main)
        XCTAssertTrue(main.contains(high))
    }
}

final class ShelfTearOffTests: XCTestCase {
    // An open notch shelf, 640 wide, hanging from the top of the screen.
    private let surface = CGRect(x: 400, y: 500, width: 640, height: 400)
    private let insets = ShellMetrics.shelfInsets(notchStyle: true, notchHeight: 32)

    func testTheStripAboveThePagesAndTheMarginsBesideThemCanStartATearOff() {
        XCTAssertTrue(ShelfTearOff.mayStart(at: CGPoint(x: 720, y: 890), surface: surface, insets: insets))
        XCTAssertTrue(ShelfTearOff.mayStart(at: CGPoint(x: 410, y: 700), surface: surface, insets: insets))
        XCTAssertTrue(ShelfTearOff.mayStart(at: CGPoint(x: 1030, y: 700), surface: surface, insets: insets))
    }

    func testThePagesThemselvesKeepTheirPresses() {
        XCTAssertFalse(ShelfTearOff.mayStart(at: CGPoint(x: 720, y: 700), surface: surface, insets: insets))
    }

    func testTheBottomMarginBelongsToTheApprovalBar() {
        XCTAssertFalse(ShelfTearOff.mayStart(at: CGPoint(x: 720, y: 505), surface: surface, insets: insets))
    }

    func testOutsideTheShelfNeverStartsOne() {
        XCTAssertFalse(ShelfTearOff.mayStart(at: CGPoint(x: 100, y: 890), surface: surface, insets: insets))
    }

    func testItTakesTheSameDeliberatePullAsTearingOffTheNotch() {
        let start = CGPoint(x: 720, y: 890)
        XCTAssertFalse(ShelfTearOff.tearsOff(from: start, to: CGPoint(x: 720, y: 860)))
        XCTAssertTrue(ShelfTearOff.tearsOff(from: start, to: CGPoint(x: 720, y: 890 - OrbGeometry.tearOffDistance)))
    }
}
