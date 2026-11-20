import CoreGraphics
import Foundation
import XCTest

@testable import WispCore

final class FuzzyMatchTests: XCTestCase {
    private func rank(_ query: String, _ names: [String]) -> [String] {
        names.compactMap { name in FuzzyMatch.score(query, in: name).map { (name, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func testAPrefixBeatsEverythingElse() {
        XCTAssertEqual(rank("saf", ["Microsoft Safety", "Safari", "Unsafe Mode"]).first, "Safari")
    }

    func testInitialsFindMultiWordNames() {
        XCTAssertNotNil(FuzzyMatch.score("vsc", in: "Visual Studio Code"))
        XCTAssertEqual(rank("vsc", ["Visual Studio Code", "VSCO Cam Helper"]).first, "VSCO Cam Helper")
        XCTAssertEqual(rank("vsco", ["Visual Studio Code", "Vscode Tools"]).first, "Vscode Tools")
    }

    func testCamelHumpsCountAsWords() {
        XCTAssertNotNil(FuzzyMatch.score("ss", in: "SoundSource"))
        XCTAssertEqual(rank("ss", ["SoundSource", "Messages"]).first, "SoundSource")
    }

    func testAWordPrefixBeatsASubstring() {
        XCTAssertEqual(rank("code", ["Xcodes", "Visual Studio Code"]).first, "Visual Studio Code")
    }

    func testSubsequencesMatchLast() {
        XCTAssertNotNil(FuzzyMatch.score("sfri", in: "Safari"))
        XCTAssertEqual(rank("ftm", ["FaceTime", "Font Manager"]).count, 2)
        XCTAssertNil(FuzzyMatch.score("xyz", in: "Safari"))
    }

    func testCaseAndAccentsAreIgnored() {
        XCTAssertNotNil(FuzzyMatch.score("CAFE", in: "Café Notes"))
        XCTAssertNotNil(FuzzyMatch.score("café", in: "Cafe Notes"))
    }

    func testShorterNamesWinWithinATier() {
        XCTAssertEqual(rank("mail", ["Mailplane Helper", "Mail"]).first, "Mail")
    }

    func testAnEmptyQueryMatchesNothing() {
        XCTAssertNil(FuzzyMatch.score("", in: "Safari"))
        XCTAssertNil(FuzzyMatch.score("  ", in: "Safari"))
    }
}

final class RingFlickTests: XCTestCase {
    private let centre = CGPoint(x: 500, y: 500)

    private func release(to point: CGPoint, held: TimeInterval = 0.1, from start: CGPoint? = nil) -> RingGesture.Outcome
    {
        let hit = RingGeometry.hit(point, centre: centre, slots: 8)
        return RingFlick.release(after: held, from: start ?? centre, to: point, centre: centre, hit: hit, slots: 8)
    }

    func testAQuickPressWithoutMovingStillLeavesTheRingOpen() {
        XCTAssertEqual(release(to: CGPoint(x: 505, y: 503)), .stayOpen)
    }

    func testAQuickFlickOntoASegmentPicksIt() {
        XCTAssertEqual(release(to: CGPoint(x: 500, y: 590)), .pick(.slot(0)))
    }

    func testOvershootingTheRingPicksByDirection() {
        XCTAssertEqual(release(to: CGPoint(x: 760, y: 500)), .pick(.slot(2)))
        XCTAssertEqual(release(to: CGPoint(x: 500, y: 260)), .pick(.slot(4)))
    }

    func testAFlickFarPastTheRingCancels() {
        XCTAssertEqual(release(to: CGPoint(x: 900, y: 500)), .close)
    }

    func testTheDirectionIsReadFromTheRingsCentre() {
        // The ring was moved off the press point to stay on screen.
        let start = CGPoint(x: 560, y: 500)
        XCTAssertEqual(release(to: CGPoint(x: 500, y: 760), from: start), .pick(.slot(0)))
    }

    func testLandingOnTheRingPicksEvenWhenItWasMovedFarFromThePress() {
        // Pressed near a corner: the ring sits 283 pt away, and the release is across it.
        XCTAssertEqual(release(to: CGPoint(x: 590, y: 500), from: CGPoint(x: 300, y: 300)), .pick(.slot(2)))
    }

    func testAHoldThatStartedOutsideAMovedRingStillClosesOutsideIt() {
        XCTAssertEqual(release(to: CGPoint(x: 820, y: 500), held: 0.6, from: CGPoint(x: 780, y: 500)), .close)
    }

    func testAThrowAcrossRatherThanOutIsNotAnOvershoot() {
        XCTAssertEqual(release(to: CGPoint(x: 700, y: 660), held: 0.6, from: CGPoint(x: 400, y: 640)), .close)
    }

    func testOvershootingAnOpenSubRingPicksItsItem() {
        let end = RingGeometry.point(at: RingGeometry.subAngle(4, count: 5, around: 0), radius: 260, from: centre)
        let outcome = RingFlick.release(
            after: 0.1, from: centre, to: end, centre: centre, hit: .none, slots: 8, expanded: 0, subItems: 5)
        XCTAssertEqual(outcome, .pick(.sub(4)))
    }

    func testALongHoldAtTheCentreStillPicksTheCentre() {
        XCTAssertEqual(release(to: CGPoint(x: 504, y: 500), held: 0.6), .pick(.centre))
    }

    func testANudgeBackIntoTheCentreDoesNothingNew() {
        XCTAssertEqual(release(to: CGPoint(x: 520, y: 500)), .stayOpen)
    }
}

final class RingKeysTests: XCTestCase {
    private func move(
        _ key: RingKey, _ hover: RingHit, expanded: Int? = nil, subItems: [Int: Int] = [:]
    ) -> RingCursor {
        RingKeys.move(key, from: RingCursor(hover: hover, expanded: expanded), slots: 4) { subItems[$0] ?? 0 }
    }

    func testArrowsStartAtTheTop() {
        XCTAssertEqual(move(.right, .none), RingCursor(hover: .slot(0), expanded: nil))
        XCTAssertEqual(move(.left, .centre), RingCursor(hover: .slot(3), expanded: nil))
    }

    func testLeftAndRightGoRoundTheRing() {
        XCTAssertEqual(move(.right, .slot(3)).hover, .slot(0))
        XCTAssertEqual(move(.left, .slot(0)).hover, .slot(3))
    }

    func testUpOpensTheSubRingAndDownComesBack() {
        let up = move(.up, .slot(2), subItems: [2: 3])
        XCTAssertEqual(up, RingCursor(hover: .sub(0), expanded: 2))
        XCTAssertEqual(move(.down, .sub(1), expanded: 2), RingCursor(hover: .slot(2), expanded: nil))
    }

    func testUpWithNoSubRingStays() {
        XCTAssertEqual(move(.up, .slot(1)), RingCursor(hover: .slot(1), expanded: nil))
    }

    func testLeftAndRightStepAlongTheSubRingAndStopAtItsEnds() {
        XCTAssertEqual(move(.right, .sub(0), expanded: 2, subItems: [2: 3]).hover, .sub(1))
        XCTAssertEqual(move(.right, .sub(2), expanded: 2, subItems: [2: 3]).hover, .sub(2))
        XCTAssertEqual(move(.left, .sub(0), expanded: 2, subItems: [2: 3]).hover, .sub(0))
    }

    func testAnEmptyRingIgnoresArrows() {
        let cursor = RingKeys.move(.right, from: RingCursor(hover: .none, expanded: nil), slots: 0) { _ in 0 }
        XCTAssertEqual(cursor.hover, .none)
    }
}

final class RingSearchTests: XCTestCase {
    private let ring = [RingAction(.home), RingAction(.clipboard), RingAction(.timer, value: "25"), RingAction(.none)]
    private let apps = [
        InstalledApp(name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app"),
        InstalledApp(name: "Calendar", bundleID: "com.apple.iCal", path: "/System/Applications/Calendar.app"),
        InstalledApp(name: "Clipboard Manager", bundleID: "x.clip", path: "/Applications/Clipboard Manager.app"),
    ]

    func testAppsAreFoundAndLaunchable() {
        let results = RingSearch.results("saf", ring: ring, apps: apps)
        XCTAssertEqual(results.first?.action, RingAction(.app, value: "com.apple.Safari", label: "Safari"))
    }

    func testRingActionsWinTies() {
        XCTAssertEqual(RingSearch.results("clip", ring: ring, apps: apps).first?.action, RingAction(.clipboard))
    }

    func testAnAppAlreadyInTheRingShowsOnce() {
        let withSafari = ring + [RingAction(.app, value: "com.apple.Safari", label: "Safari")]
        XCTAssertEqual(RingSearch.results("safari", ring: withSafari, apps: apps).count, 1)
    }

    func testNothingTypedFindsNothingAndEmptySlotsAreSkipped() {
        XCTAssertTrue(RingSearch.results("", ring: ring, apps: apps).isEmpty)
        XCTAssertTrue(RingSearch.results("nothing", ring: ring, apps: apps).isEmpty)
    }

    func testResultsAreCapped() {
        let many = (0..<20).map { InstalledApp(name: "App \($0)", bundleID: "a.\($0)", path: "/A/\($0).app") }
        XCTAssertEqual(RingSearch.results("app", ring: [], apps: many).count, RingSearch.limit)
    }
}

final class RingTypingTests: XCTestCase {
    private func command(_ code: UInt16, _ text: String = "", query: String = "", modified: Bool = false) -> RingCommand
    {
        RingTyping.command(keyCode: code, characters: text, modified: modified, query: query)
    }

    func testEscapeClearsTheSearchBeforeClosing() {
        XCTAssertEqual(command(KeyCodes.escape, query: "sa"), .clearQuery)
        XCTAssertEqual(command(KeyCodes.escape), .close)
    }

    func testDigitsPickSegmentsUntilSomethingIsTyped() {
        XCTAssertEqual(command(19, "2"), .pickSlot(1))
        XCTAssertEqual(command(19, "2", query: "x"), .type("x2"))
    }

    func testLettersStartASearch() {
        XCTAssertEqual(command(1, "s"), .type("s"))
        XCTAssertEqual(command(0, "a", query: "s"), .type("sa"))
        XCTAssertEqual(command(KeyCodes.space, " "), .ignore)
        XCTAssertEqual(command(KeyCodes.space, " ", query: "visual"), .type("visual "))
    }

    func testShortcutsAndControlCharactersAreLeftAlone() {
        XCTAssertEqual(command(1, "s", modified: true), .ignore)
        XCTAssertEqual(command(48, "\t"), .ignore)
        XCTAssertEqual(command(KeyCodes.f18, "\u{F715}"), .ignore)
        XCTAssertEqual(command(115, "\u{F729}"), .ignore)
    }

    func testDeleteEditsTheSearch() {
        XCTAssertEqual(command(RingTyping.delete, query: "sa"), .type("s"))
        XCTAssertEqual(command(RingTyping.delete, query: "s"), .clearQuery)
        XCTAssertEqual(command(RingTyping.delete), .ignore)
    }

    func testArrowsMoveRoundTheRingOrThroughResults() {
        XCTAssertEqual(command(RingTyping.right), .move(.right))
        XCTAssertEqual(command(RingTyping.up), .move(.up))
        XCTAssertEqual(command(RingTyping.down, query: "s"), .moveResult(1))
        XCTAssertEqual(command(RingTyping.up, query: "s"), .moveResult(-1))
        XCTAssertEqual(command(RingTyping.left, query: "s"), .ignore)
    }

    func testReturnPicks() {
        XCTAssertEqual(command(RingTyping.returnKey), .submit)
        XCTAssertEqual(command(RingTyping.keypadEnter, query: "s"), .submit)
    }

    func testSearchesStayShort() {
        let long = String(repeating: "a", count: RingTyping.maxQuery)
        XCTAssertEqual(command(0, "a", query: long), .ignore)
    }
}
