import XCTest

@testable import WispCore

final class NotchMachineTests: XCTestCase {
    func testHoverPeeksThenOpensAfterDwell() {
        var machine = NotchMachine()
        XCTAssertEqual(machine.handle(.pointerEntered), [.scheduleDwell])
        XCTAssertEqual(machine.phase, .peek)
        XCTAssertEqual(machine.handle(.dwellElapsed), [.cancelDwell])
        XCTAssertEqual(machine.phase, .open)
        XCTAssertFalse(machine.pinned)
    }

    func testLeavingDuringPeekCancelsTheDwell() {
        var machine = NotchMachine()
        _ = machine.handle(.pointerEntered)
        XCTAssertEqual(machine.handle(.pointerExited), [.cancelDwell])
        XCTAssertEqual(machine.phase, .closed)
    }

    func testClickModeOnlyPeeksOnHover() {
        var machine = NotchMachine(opensOnHover: false)
        XCTAssertEqual(machine.handle(.pointerEntered), [])
        XCTAssertEqual(machine.phase, .peek)
        XCTAssertEqual(machine.handle(.dwellElapsed), [.cancelDwell], "a stray dwell still opens; none is scheduled")
        var clicked = NotchMachine(opensOnHover: false)
        _ = clicked.handle(.pointerEntered)
        _ = clicked.handle(.clicked)
        XCTAssertEqual(clicked.phase, .open)
    }

    func testClickDuringPeekOpensImmediately() {
        var machine = NotchMachine()
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.clicked)
        XCTAssertEqual(machine.phase, .open)
    }

    func testHoverOpenedShelfClosesAfterDelayUnlessPointerReturns() {
        var machine = open(byHover: true)
        XCTAssertEqual(machine.handle(.pointerExited), [.scheduleClose])
        XCTAssertEqual(machine.handle(.pointerEntered), [.cancelClose])
        XCTAssertEqual(machine.phase, .open)
        _ = machine.handle(.pointerExited)
        _ = machine.handle(.closeDelayElapsed)
        XCTAssertEqual(machine.phase, .closed)
    }

    func testHotkeyOpenIsPinnedAgainstPointerExit() {
        var machine = NotchMachine()
        _ = machine.handle(.hotkey)
        XCTAssertEqual(machine.phase, .open)
        XCTAssertTrue(machine.pinned)
        XCTAssertEqual(machine.handle(.pointerExited), [])
        XCTAssertEqual(machine.phase, .open)
    }

    func testHotkeyTogglesClosed() {
        var machine = NotchMachine()
        _ = machine.handle(.hotkey)
        _ = machine.handle(.hotkey)
        XCTAssertEqual(machine.phase, .closed)
        XCTAssertFalse(machine.pinned)
    }

    func testEscapeAndOutsideClickClose() {
        var viaEscape = open(byHover: false)
        _ = viaEscape.handle(.escape)
        XCTAssertEqual(viaEscape.phase, .closed)

        var viaClick = open(byHover: false)
        _ = viaClick.handle(.clickedOutside)
        XCTAssertEqual(viaClick.phase, .closed)
    }

    func testIrrelevantEventsAreIgnored() {
        var machine = NotchMachine()
        XCTAssertEqual(machine.handle(.dwellElapsed), [])
        XCTAssertEqual(machine.handle(.closeDelayElapsed), [])
        XCTAssertEqual(machine.handle(.escape), [])
        XCTAssertEqual(machine.phase, .closed)
    }

    private func open(byHover: Bool) -> NotchMachine {
        var machine = NotchMachine()
        if byHover {
            _ = machine.handle(.pointerEntered)
            _ = machine.handle(.dwellElapsed)
        } else {
            _ = machine.handle(.hotkey)
        }
        return machine
    }

    func testDragOpensUnpinnedAndClosesOnExit() {
        var machine = NotchMachine(opensOnHover: false)
        _ = machine.handle(.dragEntered)
        XCTAssertEqual(machine.phase, .open)
        XCTAssertFalse(machine.pinned)
        XCTAssertEqual(machine.handle(.pointerExited), [.scheduleClose])
    }

    func testStaysOpenWhenPointerLeavesIfAutoCloseIsOff() {
        var machine = NotchMachine()
        machine.closing = .clickElsewhere
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.dwellElapsed)
        XCTAssertEqual(machine.handle(.pointerExited), [])
        XCTAssertEqual(machine.phase, .open)
        _ = machine.handle(.clickedOutside)
        XCTAssertEqual(machine.phase, .closed)
    }

    func testDragOpenedShelfStillClosesOnLeaveWhenAutoCloseIsOff() {
        var machine = NotchMachine()
        machine.closing = .clickElsewhere
        _ = machine.handle(.dragEntered)
        XCTAssertEqual(machine.handle(.pointerExited), [.scheduleClose])
        _ = machine.handle(.closeDelayElapsed)
        // A later hover-open stays open again.
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.dwellElapsed)
        XCTAssertEqual(machine.handle(.pointerExited), [])
    }

    func testStayOpenIgnoresClicksElsewhere() {
        var machine = NotchMachine()
        machine.closing = .never
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.clicked)
        XCTAssertEqual(machine.handle(.pointerExited), [])
        XCTAssertEqual(machine.handle(.clickedOutside), [])
        XCTAssertEqual(machine.phase, .open)
        _ = machine.handle(.escape)
        XCTAssertEqual(machine.phase, .closed)
    }

    func testStayOpenStillClosesWithTheShortcut() {
        var machine = NotchMachine()
        machine.closing = .never
        _ = machine.handle(.pointerEntered)
        _ = machine.handle(.clicked)
        _ = machine.handle(.hotkey)
        XCTAssertEqual(machine.phase, .closed)
    }

    func testDragOpenedShelfClosesOnLeaveEvenWhenStayingOpen() {
        var machine = NotchMachine()
        machine.closing = .never
        _ = machine.handle(.dragEntered)
        XCTAssertEqual(machine.handle(.pointerExited), [.scheduleClose])
    }

    func testClosingRulesFromStoredValues() {
        XCTAssertEqual(ShelfClosing(storedValue: nil, legacyAutoClose: nil), .pointerLeaves)
        XCTAssertEqual(ShelfClosing(storedValue: nil, legacyAutoClose: true), .pointerLeaves)
        XCTAssertEqual(ShelfClosing(storedValue: nil, legacyAutoClose: false), .clickElsewhere)
        XCTAssertEqual(ShelfClosing(storedValue: "never", legacyAutoClose: true), .never)
    }
}
