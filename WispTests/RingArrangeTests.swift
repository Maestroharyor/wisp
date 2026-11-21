import CoreGraphics
import Foundation
import XCTest

@testable import WispCore

final class RingArrangeTests: XCTestCase {
    private func slots(_ kinds: [RingAction.Kind]) -> [RingSlot] { kinds.map { RingSlot(RingAction($0)) } }
    private func app(_ id: String) -> RingAction { RingAction(.app, value: id, label: id) }
    private func kinds(_ slots: [RingSlot]) -> [RingAction.Kind] { slots.map(\.action.kind) }

    func testAnIconMovesToWhereItIsDropped() {
        let ring = slots([.home, .tray, .timer, .focus])
        XCTAssertEqual(kinds(RingArrange.move(ring, from: 0, to: 2)), [.tray, .timer, .home, .focus])
        XCTAssertEqual(kinds(RingArrange.move(ring, from: 3, to: 0)), [.focus, .home, .tray, .timer])
        XCTAssertEqual(kinds(RingArrange.move(ring, from: 1, to: 9)), [.home, .timer, .focus, .tray])
        XCTAssertEqual(RingArrange.move(ring, from: 7, to: 0), ring)
    }

    func testTheDropDirectionPicksThePlace() {
        XCTAssertEqual(RingArrange.index(at: 0, count: 4), 0)
        XCTAssertEqual(RingArrange.index(at: 92, count: 4), 1)
        XCTAssertEqual(RingArrange.index(at: 350, count: 4), 0)
        XCTAssertEqual(RingArrange.index(at: -90, count: 4), 3)
        XCTAssertEqual(RingArrange.index(at: 45, count: 0), 0)
    }

    func testRemovingTakesOnlyThatIcon() {
        let ring = slots([.home, .tray, .timer])
        XCTAssertEqual(kinds(RingArrange.remove(ring, at: 1)), [.home, .timer])
        XCTAssertEqual(RingArrange.remove(ring, at: 5), ring)
    }

    func testDroppedAppsAreAddedWhereTheyLand() {
        let ring = slots([.home, .tray])
        guard case .added(let added) = RingArrange.insert([app("a"), app("b")], into: ring, at: 1) else {
            return XCTFail("not added")
        }
        XCTAssertEqual(added.map(\.action.title), ["Home", "a", "b", "Tray"])
    }

    func testAppsAlreadyOnTheRingArentAddedTwice() {
        let ring = [RingSlot(app("a")), RingSlot(RingAction(.home))]
        XCTAssertEqual(RingArrange.insert([app("a")], into: ring, at: 0), .alreadyThere)
        guard case .added(let added) = RingArrange.insert([app("b"), app("b"), app("a")], into: ring, at: 2) else {
            return XCTFail("not added")
        }
        XCTAssertEqual(added.count, 3)
    }

    func testLinksAndFoldersAlreadyOnTheRingArentAddedTwice() {
        let site = RingAction(.link, value: "https://example.com")
        let ring = [RingSlot(site), RingSlot(RingAction(.folder, value: "/Users/me/Downloads"))]
        XCTAssertEqual(RingArrange.insert([site], into: ring, at: 2), .alreadyThere)
        XCTAssertEqual(
            RingArrange.insert([RingAction(.folder, value: "/Users/me/Downloads")], into: ring, at: 2), .alreadyThere)
        guard
            case .added(let added) = RingArrange.insert(
                [RingAction(.link, value: "https://other.com")], into: ring, at: 2)
        else { return XCTFail("not added") }
        XCTAssertEqual(added.count, 3)
    }

    func testAFullRingTakesNoMore() {
        let full = Array(repeating: RingSlot(RingAction(.home)), count: RingSet.maxSlots)
        XCTAssertEqual(RingArrange.insert([app("a")], into: full, at: 0), .full)
        let almost = Array(full.dropLast())
        guard case .added(let added) = RingArrange.insert([app("a"), app("b")], into: almost, at: 0) else {
            return XCTFail("not added")
        }
        XCTAssertEqual(added.count, RingSet.maxSlots)
    }

    func testOnlyAppsDroppedOutsideAFolderArePinned() {
        XCTAssertTrue(RingPinDrop.pins(paths: ["/Applications/Safari.app", "/Applications/Xcode.APP"], onto: nil))
        XCTAssertTrue(RingPinDrop.pins(paths: ["/Applications/Safari.app"], onto: .app))
        XCTAssertFalse(RingPinDrop.pins(paths: ["/Applications/Safari.app"], onto: .folder))
        XCTAssertFalse(RingPinDrop.pins(paths: ["/Applications/Safari.app", "/tmp/a.pdf"], onto: nil))
        XCTAssertFalse(RingPinDrop.pins(paths: [], onto: nil))
    }

    func testRunningAppsFillTheFreePlacesInOrder() {
        let pinned = [RingSlot(app("safari")), RingSlot(RingAction(.home))]
        let running = [
            RunningApp(bundleID: "safari", name: "Safari"), RunningApp(bundleID: "xcode", name: "Xcode"),
            RunningApp(bundleID: "xcode", name: "Xcode"), RunningApp(bundleID: "music", name: "Music"),
        ]
        let filled = RingRunning.fill(pinned, running: running)
        XCTAssertEqual(filled.map(\.action.title), ["safari", "Home", "Xcode", "Music"])
        XCTAssertEqual(RingRunning.fill(pinned, running: running, limit: 3).count, 3)
    }
}
