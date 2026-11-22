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
}
