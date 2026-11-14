import XCTest

@testable import WispCore

final class PillDestinationTests: XCTestCase {
    func testLivePillsOpenTheirOwnView() {
        XCTAssertEqual(PillDestination(slot: .agent), .agents)
        XCTAssertEqual(PillDestination(slot: .timer), .timer)
        XCTAssertEqual(PillDestination(slot: .media), .nowPlaying)
        XCTAssertEqual(PillDestination(slot: .download), .downloads)
        XCTAssertEqual(PillDestination(slot: .external), .externalDetails)
        XCTAssertEqual(PillDestination(slot: .regionWatch), .regionWatch)
    }

    func testAlertsWithAMatchingViewOpenIt() {
        XCTAssertEqual(PillDestination(slot: .timerDone), .timer)
        XCTAssertEqual(PillDestination(slot: .tray), .tray)
        XCTAssertEqual(PillDestination(slot: .battery), .battery)
    }

    func testEverythingElseKeepsTheUsualPage() {
        let usual: [ActivitySlot] = [
            .notice, .notification, .focus, .capsLock, .level, .agentApproval, .meeting, .meetingSoon, .device,
            .dictation, .downloadDone, .aiResult, .agentCallout, .agentAway,
        ]
        for slot in usual {
            XCTAssertEqual(PillDestination(slot: slot), .home, "\(slot)")
        }
    }

    func testNoPillMeansTheUsualPage() {
        XCTAssertEqual(PillDestination(slot: nil), .home)
    }

    func testEverySlotHasADestination() {
        // A new slot has to be placed on purpose: this fails to compile until it is.
        for slot in ActivitySlot.allCases {
            _ = PillDestination(slot: slot)
        }
    }
}
