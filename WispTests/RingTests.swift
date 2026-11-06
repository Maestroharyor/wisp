import CoreGraphics
import Foundation
import XCTest

@testable import WispCore

final class RingGeometryTests: XCTestCase {
    private let centre = CGPoint(x: 500, y: 500)

    func testSlotsStartAtTwelveAndRunClockwise() {
        XCTAssertEqual(RingGeometry.slotAngle(0, count: 8), 0)
        XCTAssertEqual(RingGeometry.slotAngle(2, count: 8), 90)
        XCTAssertEqual(RingGeometry.slotAngle(1, count: 3), 120)
        for count in 1...8 {
            for index in 0..<count {
                let angle = RingGeometry.slotAngle(index, count: count)
                let point = RingGeometry.point(at: angle, radius: RingGeometry.ringRadius, from: centre)
                XCTAssertEqual(RingGeometry.hit(point, centre: centre, slots: count), .slot(index), "\(index)/\(count)")
            }
        }
    }

    func testPointsUseAppKitCoordinates() {
        let up = RingGeometry.point(at: 0, radius: 100, from: centre)
        XCTAssertEqual(up.x, 500, accuracy: 0.001)
        XCTAssertEqual(up.y, 600, accuracy: 0.001)
        let right = RingGeometry.point(at: 90, radius: 100, from: centre)
        XCTAssertEqual(right.x, 600, accuracy: 0.001)
    }

    func testTheMiddleIsTheCentreButton() {
        XCTAssertEqual(RingGeometry.hit(CGPoint(x: 510, y: 505), centre: centre, slots: 8), .centre)
    }

    func testSegmentBoundariesSplitHalfway() {
        // With 4 slots, 44° still belongs to slot 0 and 46° to slot 1.
        let radius = RingGeometry.ringRadius
        let a = RingGeometry.point(at: 44, radius: radius, from: centre)
        let b = RingGeometry.point(at: 46, radius: radius, from: centre)
        XCTAssertEqual(RingGeometry.hit(a, centre: centre, slots: 4), .slot(0))
        XCTAssertEqual(RingGeometry.hit(b, centre: centre, slots: 4), .slot(1))
        let wrap = RingGeometry.point(at: 350, radius: radius, from: centre)
        XCTAssertEqual(RingGeometry.hit(wrap, centre: centre, slots: 4), .slot(0))
    }

    func testTheSubRingSitsOutsideItsSlot() {
        let parent = RingGeometry.slotAngle(2, count: 8)
        for index in 0..<3 {
            let angle = RingGeometry.subAngle(index, count: 3, around: parent)
            let point = RingGeometry.point(at: angle, radius: RingGeometry.subRadius, from: centre)
            XCTAssertEqual(
                RingGeometry.hit(point, centre: centre, slots: 8, expanded: 2, subItems: 3), .sub(index))
        }
        let away = RingGeometry.point(at: 270, radius: RingGeometry.subRadius, from: centre)
        XCTAssertEqual(RingGeometry.hit(away, centre: centre, slots: 8, expanded: 2, subItems: 3), .none)
        let collapsed = RingGeometry.point(at: parent, radius: RingGeometry.subRadius, from: centre)
        XCTAssertEqual(RingGeometry.hit(collapsed, centre: centre, slots: 8), .none)
    }

    func testTheRingStaysOnScreen() {
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 874)
        let reach = RingGeometry.subOuter + RingGeometry.margin
        for requested in [CGPoint(x: 0, y: 0), CGPoint(x: 1512, y: 944), CGPoint(x: 756, y: 500)] {
            let fitted = RingGeometry.fittedCentre(requested, in: visible)
            XCTAssertGreaterThanOrEqual(fitted.x - reach, visible.minX)
            XCTAssertLessThanOrEqual(fitted.x + reach, visible.maxX)
            XCTAssertGreaterThanOrEqual(fitted.y - reach, visible.minY)
            XCTAssertLessThanOrEqual(fitted.y + reach, visible.maxY)
        }
        XCTAssertEqual(RingGeometry.fittedCentre(CGPoint(x: 756, y: 500), in: visible), CGPoint(x: 756, y: 500))
    }

    func testTheRingKeepsBelowASystemIsland() {
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 874)
        let plain = RingGeometry.fittedCentre(CGPoint(x: 756, y: 944), in: visible)
        let clear = RingGeometry.fittedCentre(CGPoint(x: 756, y: 944), in: visible, avoidsTopCentre: true)
        XCTAssertLessThan(clear.y, plain.y)
    }
}

final class RingShapeTests: XCTestCase {
    func testWedgesSplitTheCircleWithGaps() {
        let first = RingGeometry.sector(0, count: 8)
        XCTAssertEqual(first.start, -22.5 + RingGeometry.gap / 2, accuracy: 0.001)
        XCTAssertEqual(first.end, 22.5 - RingGeometry.gap / 2, accuracy: 0.001)
        let next = RingGeometry.sector(1, count: 8)
        XCTAssertEqual(next.start - first.end, RingGeometry.gap, accuracy: 0.001)
        XCTAssertEqual(RingGeometry.sector(0, count: 0).start, 0)
    }

    func testSubWedgesCentreOnTheirItems() {
        let wedge = RingGeometry.subSector(0, count: 3, around: 90)
        XCTAssertEqual((wedge.start + wedge.end) / 2, RingGeometry.subAngle(0, count: 3, around: 90), accuracy: 0.001)
        XCTAssertEqual(wedge.end - wedge.start, RingGeometry.subStep - RingGeometry.gap, accuracy: 0.001)
    }

    func testSegmentsFlyOutInTurn() {
        XCTAssertEqual(RingGeometry.delay(for: 0), 0)
        XCTAssertEqual(RingGeometry.delay(for: 3), 3 * RingGeometry.stagger, accuracy: 0.0001)
        XCTAssertEqual(RingGeometry.delay(for: -1), 0)
    }

    func testTheWholeWedgeCountsAsTheSegment() {
        let centre = CGPoint(x: 0, y: 0)
        for radius in [RingGeometry.ringInner + 1, RingGeometry.ringOuter - 1] {
            let point = RingGeometry.point(at: 90, radius: radius, from: centre)
            XCTAssertEqual(RingGeometry.hit(point, centre: centre, slots: 8), .slot(2))
        }
    }
}

final class RingConfigTests: XCTestCase {
    func testTheDefaultRingIsFullAndUseful() {
        let slots = RingConfig.defaults.standard.slots
        XCTAssertEqual(slots.count, RingSet.maxSlots)
        XCTAssertTrue(slots.contains { !$0.group.isEmpty })
        XCTAssertTrue(slots.contains { $0.action.kind == .agents })
    }

    func testSetsAndGroupsAreCapped() {
        let many = Array(repeating: RingSlot(RingAction(.home)), count: 12)
        XCTAssertEqual(RingSet(name: "x", slots: many).slots.count, 8)
        let group = Array(repeating: RingAction(.zip), count: 12)
        XCTAssertEqual(RingSlot(RingAction(.zip), group: group).group.count, 9)
    }

    func testTheFrontAppPicksItsSet() {
        let terminal = RingSet(
            name: "Terminal", slots: [RingSlot(RingAction(.agents))], bundleIDs: ["com.apple.Terminal"])
        let config = RingConfig(standard: RingConfig.defaults.standard, perApp: [terminal])
        XCTAssertEqual(config.set(forFrontApp: "com.apple.Terminal"), terminal)
        XCTAssertEqual(config.set(forFrontApp: "com.apple.Safari"), config.standard)
        XCTAssertEqual(config.set(forFrontApp: nil), config.standard)
    }

    func testItRoundTripsAndSurvivesUnknownActions() throws {
        let data = try JSONEncoder().encode(RingConfig.defaults)
        XCTAssertEqual(try JSONDecoder().decode(RingConfig.self, from: data), RingConfig.defaults)
        let future = #"{"kind":"teleport","value":"x"}"#.data(using: .utf8) ?? Data()
        XCTAssertEqual(try JSONDecoder().decode(RingAction.self, from: future).kind, .none)
    }

    func testSegmentsKeepTheirIdsAndOldRingsGetNewOnes() throws {
        var slot = RingSlot(RingAction(.home))
        let id = slot.id
        slot.setGroup(Array(repeating: RingAction(.zip), count: 12))
        XCTAssertEqual(slot.id, id)
        XCTAssertEqual(slot.group.count, RingSlot.maxSubItems)
        let data = try JSONEncoder().encode(slot)
        XCTAssertEqual(try JSONDecoder().decode(RingSlot.self, from: data).id, id)
        let old = #"{"action":{"kind":"home"}}"#.data(using: .utf8) ?? Data()
        let a = try JSONDecoder().decode(RingSlot.self, from: old)
        let b = try JSONDecoder().decode(RingSlot.self, from: old)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.action.kind, .home)
    }

    func testActionsKnowWhatTakesFiles() {
        XCTAssertTrue(RingAction(.airDrop).acceptsFiles)
        XCTAssertTrue(RingAction(.dropAction, value: "id").acceptsFiles)
        XCTAssertFalse(RingAction(.playPause).acceptsFiles)
    }

    func testTimerMinutesFallBack() {
        XCTAssertEqual(RingAction(.timer, value: "10").minutes, 10)
        XCTAssertEqual(RingAction(.timer).minutes, 25)
        XCTAssertEqual(RingAction(.timer, value: "abc").minutes, 25)
        XCTAssertEqual(RingAction(.timer, value: "10").title, "10 min timer")
    }
}

final class RingChoiceTests: XCTestCase {
    func testWaitingRequestsComeFirstAsAllowAndDeny() {
        let id = UUID()
        let choices = RingAgentChoices.choices(for: [
            RingAgentEntry(sessionID: "a", project: "wisp", approvalID: id),
            RingAgentEntry(sessionID: "b", project: "site"),
        ])
        XCTAssertEqual(choices.map(\.id), ["allow:\(id.uuidString)", "deny:\(id.uuidString)"])
        XCTAssertEqual(choices.map(\.tint), [.allow, .deny])
        XCTAssertEqual(choices.first?.title, "Allow wisp")
    }

    func testWithNothingWaitingEachSessionShowsItsTerminal() {
        let choices = RingAgentChoices.choices(for: [
            RingAgentEntry(sessionID: "a", project: "wisp"), RingAgentEntry(sessionID: "b", project: "site"),
        ])
        XCTAssertEqual(choices.map(\.id), ["focus:a", "focus:b"])
    }

    func testChoicesAreCapped() {
        let entries = (0..<8).map { RingAgentEntry(sessionID: "\($0)", project: "p\($0)", approvalID: UUID()) }
        XCTAssertEqual(RingAgentChoices.choices(for: entries).count, RingSlot.maxSubItems)
    }
}

final class RingGestureTests: XCTestCase {
    func testAQuickPressLeavesTheRingOpen() {
        XCTAssertEqual(RingGesture.release(after: 0.1, on: .slot(2)), .stayOpen)
    }

    func testAHoldPicksWhereItLetsGo() {
        XCTAssertEqual(RingGesture.release(after: 0.6, on: .slot(2)), .pick(.slot(2)))
        XCTAssertEqual(RingGesture.release(after: 0.6, on: .sub(1)), .pick(.sub(1)))
        XCTAssertEqual(RingGesture.release(after: 0.6, on: .none), .close)
    }
}

final class RingButtonTests: XCTestCase {
    func testButtonsMapToCGEventNumbers() {
        XCTAssertNil(RingButton.off.number)
        XCTAssertEqual(RingButton.middle.number, 2)
        XCTAssertEqual(RingButton.back.number, 3)
        XCTAssertEqual(RingButton.forward.number, 4)
    }
}

final class RingInteractionTests: XCTestCase {
    private let slots = RingConfig.defaults.standard.slots
    private func hasSub(_ index: Int) -> Bool { !slots[index].group.isEmpty }

    func testASubRingStaysOpenOnTheWayOut() {
        // Media is slot 2; heading out to its first item crosses slot 1's wedge.
        let outer = RingGeometry.ringRadius + 10
        XCTAssertEqual(
            RingInteraction.expanded(current: 2, hit: .slot(1), distance: outer, hasSubItems: hasSub), 2)
        XCTAssertEqual(
            RingInteraction.expanded(current: 2, hit: .none, distance: 400, hasSubItems: hasSub), 2)
    }

    func testInsideTheSegmentsTheHoveredSegmentDecides() {
        let inner = RingGeometry.ringRadius - 10
        XCTAssertNil(RingInteraction.expanded(current: 2, hit: .slot(1), distance: inner, hasSubItems: hasSub))
        XCTAssertEqual(
            RingInteraction.expanded(current: nil, hit: .slot(2), distance: inner, hasSubItems: hasSub), 2)
        XCTAssertEqual(
            RingInteraction.expanded(current: nil, hit: .slot(2), distance: inner + 20, hasSubItems: hasSub), 2)
        XCTAssertNil(RingInteraction.expanded(current: 2, hit: .centre, distance: 0, hasSubItems: hasSub))
    }

    func testEverySubItemOfTheMediaRingIsReachableInAStraightLine() {
        let centre = CGPoint(x: 0, y: 0)
        let parent = RingGeometry.slotAngle(2, count: slots.count)
        for item in 0..<3 {
            let angle = RingGeometry.subAngle(item, count: 3, around: parent)
            var expanded: Int?
            var last: RingHit = .none
            for step in stride(from: CGFloat(10), through: RingGeometry.subRadius, by: 4) {
                let point = RingGeometry.point(at: angle, radius: step, from: centre)
                // The pointer passes over the media segment itself first.
                let hit = RingGeometry.hit(
                    point, centre: centre, slots: slots.count, expanded: expanded, subItems: expanded == nil ? 0 : 3)
                let onParent = step < RingGeometry.ringRadius ? RingHit.slot(2) : hit
                expanded = RingInteraction.expanded(
                    current: expanded, hit: onParent, distance: step, hasSubItems: hasSub)
                last = hit
            }
            XCTAssertEqual(last, .sub(item), "item \(item)")
        }
    }

    func testPicks() {
        XCTAssertEqual(
            RingInteraction.outcome(of: .centre, slots: slots, expanded: nil, subItemCount: 0, hasFiles: false),
            .openShelf)
        XCTAssertEqual(
            RingInteraction.outcome(of: .centre, slots: slots, expanded: nil, subItemCount: 0, hasFiles: true),
            .keepFiles)
        XCTAssertEqual(
            RingInteraction.outcome(of: .slot(1), slots: slots, expanded: nil, subItemCount: 2, hasFiles: false),
            .expand(1))
        XCTAssertEqual(
            RingInteraction.outcome(of: .slot(1), slots: slots, expanded: 1, subItemCount: 2, hasFiles: false),
            .run(slot: 1))
        XCTAssertEqual(
            RingInteraction.outcome(of: .slot(1), slots: slots, expanded: nil, subItemCount: 0, hasFiles: false),
            .run(slot: 1))
        XCTAssertEqual(
            RingInteraction.outcome(of: .sub(2), slots: slots, expanded: 2, subItemCount: 3, hasFiles: false),
            .runSub(slot: 2, item: 2))
        XCTAssertEqual(
            RingInteraction.outcome(of: .sub(5), slots: slots, expanded: 2, subItemCount: 3, hasFiles: false),
            .close)
        XCTAssertEqual(
            RingInteraction.outcome(of: .slot(12), slots: slots, expanded: nil, subItemCount: 0, hasFiles: false),
            .close)
        XCTAssertEqual(
            RingInteraction.outcome(of: .none, slots: slots, expanded: nil, subItemCount: 0, hasFiles: false),
            .close)
    }
}

final class RingFormTests: XCTestCase {
    func testFormChoicesMarkTheCurrentForm() {
        let choices = RingFormChoices.choices(current: .orb, systemIsland: false)
        XCTAssertEqual(choices.map(\.id), FormFactor.allCases.map { "form:\($0.rawValue)" })
        XCTAssertEqual(choices.first { $0.id == "form:orb" }?.tint, .allow)
        XCTAssertFalse(
            RingFormChoices.choices(current: .orb, systemIsland: true).contains { $0.id == "form:notch" })
    }

    func testPickingFormOpensItsChoices() {
        let slots = [RingSlot(RingAction(.form))]
        XCTAssertEqual(
            RingInteraction.outcome(of: .slot(0), slots: slots, expanded: nil, subItemCount: 5, hasFiles: false),
            .expand(0))
        XCTAssertTrue(RingAction(.form).opensChoices)
        XCTAssertFalse(RingAction(.home).opensChoices)
    }
}
