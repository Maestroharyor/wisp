import XCTest

@testable import WispCore

final class ConvertTargetsTests: XCTestCase {
    func testEachKindOffersItsFormats() {
        XCTAssertEqual(ConvertTargets.formats(forExtensions: ["png"]), [.jpeg, .heic, .tiff, .gif])
        XCTAssertEqual(ConvertTargets.formats(forExtensions: ["MOV"]), [.mp4, .gif, .m4a])
        XCTAssertEqual(ConvertTargets.formats(forExtensions: ["mp3"]), [.m4a, .wav, .aiff])
    }

    func testTheSourceFormatIsLeftOutOnlyWhenAllFilesShareIt() {
        XCTAssertFalse(ConvertTargets.formats(forExtensions: ["jpeg", "JPG"]).contains(.jpeg))
        XCTAssertTrue(ConvertTargets.formats(forExtensions: ["jpg", "png"]).contains(.jpeg))
        XCTAssertFalse(ConvertTargets.formats(forExtensions: ["aif"]).contains(.aiff))
    }

    func testMixedFilesOnlyOfferWhatEveryOneCanBecome() {
        XCTAssertEqual(ConvertTargets.formats(forExtensions: ["png", "mov"]), [.gif])
        XCTAssertEqual(ConvertTargets.formats(forExtensions: ["mov", "wav"]), [.m4a])
        XCTAssertTrue(ConvertTargets.formats(forExtensions: ["png", "pdf"]).isEmpty)
        XCTAssertTrue(ConvertTargets.formats(forExtensions: []).isEmpty)
    }

    func testChoicesAreNumberedAndEndWithThePanel() {
        let choices = ConvertTargets.choices(for: [.mp4, .gif])
        XCTAssertEqual(choices.map(\.title), ["1  MP4", "2  GIF", "More…"])
        XCTAssertEqual(choices.first.flatMap(ConvertTargets.format(of:)), .mp4)
        XCTAssertNil(choices.last.flatMap(ConvertTargets.format(of:)))
        XCTAssertTrue(ConvertTargets.choices(for: []).isEmpty)
    }

    func testAGIFTakesTenFramesASecondForAtMostFifteenSeconds() {
        XCTAssertEqual(GIFPlan.frames(duration: 1).count, 10)
        XCTAssertEqual(GIFPlan.frames(duration: 60).count, 150)
        XCTAssertEqual(GIFPlan.frames(duration: 0.05), [0])
        XCTAssertTrue(GIFPlan.frames(duration: .nan).isEmpty)
        XCTAssertEqual(GIFPlan.delay(), 0.1, accuracy: 0.0001)
    }

    func testSilentVideosDontOfferM4A() {
        XCTAssertFalse(ConvertTargets.formats(forExtensions: ["mov"], videosHaveSound: false).contains(.m4a))
        XCTAssertTrue(ConvertTargets.formats(forExtensions: ["mov"], videosHaveSound: true).contains(.m4a))
        XCTAssertTrue(ConvertTargets.formats(forExtensions: ["mov"], videosHaveSound: nil).contains(.m4a))
        XCTAssertTrue(
            ConvertTargets.formats(forExtensions: ["mp3"], videosHaveSound: false).contains(.m4a),
            "audio keeps M4A")
    }

    func testADragAddsTransformToARingWithoutIt() {
        let plain = RingSet(name: "Default", slots: [RingSlot(RingAction(.home))])
        XCTAssertEqual(RingDropSet.withTransform(plain).slots.map(\.action.kind), [.home, .transform])
        let has = RingSet(name: "Default", slots: [RingSlot(RingAction(.transform)), RingSlot(RingAction(.tray))])
        XCTAssertEqual(RingDropSet.withTransform(has).slots.count, 2)
        let full = RingSet(
            name: "Full",
            slots: (0..<RingSet.maxSlots - 1).map { _ in RingSlot(RingAction(.tray)) } + [RingSlot(RingAction(.home))])
        let lent = RingDropSet.withTransform(full)
        XCTAssertEqual(lent.slots.count, RingSet.maxSlots)
        XCTAssertEqual(lent.slots.last?.action.kind, .transform, "takes the place of one that can't take files")
        let allFiles = RingSet(name: "Files", slots: (0..<RingSet.maxSlots).map { _ in RingSlot(RingAction(.tray)) })
        XCTAssertEqual(RingDropSet.withTransform(allFiles).slots.map(\.action.kind), allFiles.slots.map(\.action.kind))
    }
}
