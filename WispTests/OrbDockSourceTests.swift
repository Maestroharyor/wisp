import XCTest

@testable import WispCore

final class OrbDockSourceTests: XCTestCase {
    private let ring = RingSet(
        name: "Default",
        slots: [
            RingSlot(RingAction(.app, value: "com.apple.finder", label: "Finder")),
            RingSlot(RingAction(.home)),
        ])

    func testRingAppsAreTheRingsOwn() {
        let apps = RingDock.apps(source: .ring, ring: ring, running: [], chosen: [])
        XCTAssertEqual(apps.compactMap(\.value), ["com.apple.finder"])
    }

    func testOpenAppsComeOnceInOrderUpToTheLimit() {
        let running =
            (1...10).map { RunningApp(bundleID: "app.\($0)", name: "App \($0)") } + [
                RunningApp(bundleID: "app.1", name: "App 1")
            ]
        let apps = RingDock.apps(source: .running, ring: ring, running: running, chosen: [])
        XCTAssertEqual(apps.count, RingDock.size)
        XCTAssertEqual(apps.first?.value, "app.1")
        XCTAssertEqual(apps.first?.title, "App 1")
    }

    func testChosenAppsKeepTheirOrderAndSkipBlanks() {
        let apps = RingDock.apps(
            source: .chosen, ring: ring, running: [], chosen: ["com.b", "", "com.a", "com.b"], names: ["com.a": "A"])
        XCTAssertEqual(apps.compactMap(\.value), ["com.b", "com.a"])
        XCTAssertEqual(apps.last?.title, "A")
    }

    func testTextScaleReadsUnknownValuesAsDefault() {
        XCTAssertEqual(TextScale(storedValue: nil), .standard)
        XCTAssertEqual(TextScale(storedValue: "huge"), .standard)
        XCTAssertEqual(TextScale(storedValue: "larger").factor, 1.25)
        XCTAssertGreaterThan(TextScale.large.factor, TextScale.standard.factor)
    }
}
