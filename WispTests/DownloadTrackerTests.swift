import XCTest

@testable import WispCore

final class DownloadTrackerTests: XCTestCase {
    private let folder = "/Users/test/Downloads"
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func file(_ name: String, _ size: Int64, total: Int64? = nil, in folder: String? = nil) -> DownloadFile {
        DownloadFile(folder: folder ?? self.folder, name: name, size: size, total: total)
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    // MARK: Partial names

    func testRecognisesEachBrowsersPartialFile() {
        XCTAssertEqual(PartialName("report.pdf.crdownload"), PartialName(kind: .chromium, finalName: "report.pdf"))
        XCTAssertEqual(PartialName("report.pdf.download"), PartialName(kind: .safari, finalName: "report.pdf"))
        XCTAssertEqual(PartialName("report.pdf.part"), PartialName(kind: .firefox, finalName: "report.pdf"))
        XCTAssertEqual(PartialName("Movie.MP4.CRDOWNLOAD")?.finalName, "Movie.MP4")
    }

    func testChromeUnconfirmedFilesHaveNoNameYet() {
        XCTAssertEqual(PartialName("Unconfirmed 123456.crdownload"), PartialName(kind: .chromium, finalName: nil))
    }

    func testIgnoresOrdinaryHiddenAndEmptyNames() {
        XCTAssertNil(PartialName("report.pdf"))
        XCTAssertNil(PartialName(".hidden.part"))
        XCTAssertNil(PartialName(".crdownload"))
        XCTAssertNil(PartialName("part"))
    }

    func testFinalExtensionIsLowercased() {
        XCTAssertEqual(PartialName("a1B2c3.ZIP.part")?.finalExtension, "zip")
        XCTAssertEqual(PartialName("Unconfirmed 1.crdownload")?.finalExtension, "")
    }

    // MARK: Progress

    func testLeftoverPartialsStayHiddenUntilTheyGrow() {
        var tracker = DownloadTracker()
        _ = tracker.update([file("old.zip.crdownload", 500)], now: at(0))
        XCTAssertTrue(tracker.downloads(now: at(0)).isEmpty)
        _ = tracker.update([file("old.zip.crdownload", 500)], now: at(5))
        XCTAssertTrue(tracker.downloads(now: at(5)).isEmpty)
        _ = tracker.update([file("old.zip.crdownload", 900)], now: at(6))
        XCTAssertEqual(tracker.downloads(now: at(6)).map(\.name), ["old.zip"])
    }

    func testANewPartialShowsRightAway() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("new.dmg.crdownload", 0)], now: at(1))
        let download = try? XCTUnwrap(tracker.downloads(now: at(1)).first)
        XCTAssertEqual(download?.name, "new.dmg")
        XCTAssertEqual(download?.received, 0)
        XCTAssertNil(download?.fraction)
    }

    func testIndeterminateWithoutATotalButReportsBytesAndRate() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.iso.part", 1_000_000)], now: at(1))
        _ = tracker.update([file("a.iso.part", 3_000_000)], now: at(2))
        _ = tracker.update([file("a.iso.part", 5_000_000)], now: at(3))
        let download = tracker.downloads(now: at(3))[0]
        XCTAssertNil(download.fraction)
        XCTAssertNil(download.remaining)
        XCTAssertEqual(download.received, 5_000_000)
        XCTAssertEqual(download.bytesPerSecond ?? 0, 2_000_000, accuracy: 1)
    }

    func testDeterminateWhenTheTotalIsKnown() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.zip.download", 2_000, total: 10_000)], now: at(1))
        _ = tracker.update([file("a.zip.download", 4_000, total: 10_000)], now: at(2))
        let download = tracker.downloads(now: at(2))[0]
        XCTAssertEqual(download.fraction ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(download.remaining ?? 0, 3, accuracy: 0.01)
    }

    func testFractionIsCappedAndIgnoresNonsenseTotals() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.download", 12, total: 10), file("b.download", 5, total: 0)], now: at(1))
        let byName = Dictionary(uniqueKeysWithValues: tracker.downloads(now: at(1)).map { ($0.name, $0) })
        XCTAssertEqual(byName["a"]?.fraction, 1)
        XCTAssertNil(byName["b"]?.fraction)
    }

    func testRateUsesOnlyRecentSamples() {
        var tracker = DownloadTracker(rateWindow: 5)
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.part", 0)], now: at(1))
        _ = tracker.update([file("a.part", 100_000_000)], now: at(2))
        for second in 3...12 {
            _ = tracker.update([file("a.part", 100_000_000 + Int64(second - 2) * 1_000)], now: at(TimeInterval(second)))
        }
        XCTAssertEqual(tracker.downloads(now: at(12))[0].bytesPerSecond ?? 0, 1_000, accuracy: 1)
    }

    func testStallsAfterNoGrowth() {
        var tracker = DownloadTracker(stallAfter: 30)
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.part", 10)], now: at(1))
        _ = tracker.update([file("a.part", 20)], now: at(2))
        XCTAssertFalse(tracker.downloads(now: at(20))[0].isStalled)
        _ = tracker.update([file("a.part", 20)], now: at(40))
        let stalled = tracker.downloads(now: at(40))[0]
        XCTAssertTrue(stalled.isStalled)
        XCTAssertNil(stalled.bytesPerSecond)
        _ = tracker.update([file("a.part", 30)], now: at(41))
        XCTAssertFalse(tracker.downloads(now: at(41))[0].isStalled)
    }

    func testForgetsDownloadsStuckForALongTime() {
        var tracker = DownloadTracker(forgetAfter: 600)
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.part", 10)], now: at(1))
        XCTAssertEqual(tracker.downloads(now: at(500)).count, 1)
        XCTAssertTrue(tracker.downloads(now: at(700)).isEmpty)
        XCTAssertTrue(tracker.isWatching(now: at(500)))
        XCTAssertFalse(tracker.isWatching(now: at(700)))
    }

    func testAPausedDownloadLetsGoOfThePillAfterTwoMinutes() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.part", 10)], now: at(1))
        XCTAssertTrue(tracker.downloads(now: at(100))[0].isStalled)
        XCTAssertTrue(tracker.downloads(now: at(122)).isEmpty)
    }

    func testNewestDownloadComesFirst() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("first.part", 1)], now: at(1))
        _ = tracker.update([file("first.part", 2), file("second.crdownload", 1)], now: at(2))
        XCTAssertEqual(tracker.downloads(now: at(2)).map(\.name), ["second", "first"])
        XCTAssertEqual(tracker.summary(now: at(2))?.primary.name, "second")
        XCTAssertEqual(tracker.summary(now: at(2))?.count, 2)
    }

    func testUnnamedChromeDownloadsGetAPlaceholderName() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("Unconfirmed 42.crdownload", 1)], now: at(1))
        XCTAssertEqual(tracker.downloads(now: at(1))[0].name, "Download")
    }

    func testSameNameInTwoFoldersAreTwoDownloads() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.part", 1), file("a.part", 1, in: "/Users/test/Desktop")], now: at(1))
        XCTAssertEqual(tracker.downloads(now: at(1)).count, 2)
    }

    // MARK: Completion

    func testChromeFinishesWhenThePartialBecomesTheFinalFile() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("app.dmg.crdownload", 100)], now: at(1))
        let done = tracker.update([file("app.dmg", 400)], now: at(2))
        XCTAssertEqual(done, [FinishedDownload(folder: folder, name: "app.dmg", size: 400)])
        XCTAssertEqual(done.first?.path, "/Users/test/Downloads/app.dmg")
        XCTAssertNil(tracker.summary(now: at(2)))
        XCTAssertFalse(tracker.isWatching(now: at(2)))
    }

    func testSafariFinishesWhenTheBundleIsReplaced() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("photo.heic.download", 10, total: 50)], now: at(1))
        XCTAssertEqual(tracker.update([file("photo.heic", 50)], now: at(2)).map(\.name), ["photo.heic"])
    }

    func testFirefoxFinishesWhenItsEmptyPlaceholderFillsUp() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("song.mp3", 0), file("Xk2p9QwE.mp3.part", 100)], now: at(1))
        XCTAssertTrue(tracker.update([file("song.mp3", 0), file("Xk2p9QwE.mp3.part", 200)], now: at(2)).isEmpty)
        let done = tracker.update([file("song.mp3", 900)], now: at(3))
        XCTAssertEqual(done.map(\.name), ["song.mp3"])
    }

    func testACancelledDownloadIsNotAnnounced() {
        var tracker = DownloadTracker()
        _ = tracker.update([file("keep.txt", 5)], now: at(0))
        _ = tracker.update([file("keep.txt", 5), file("big.zip.crdownload", 100)], now: at(1))
        XCTAssertTrue(tracker.update([file("keep.txt", 5)], now: at(2)).isEmpty)
        XCTAssertNil(tracker.summary(now: at(2)))
    }

    func testAnUnrelatedNewFileIsNotMistakenForTheDownload() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("big.zip.crdownload", 100)], now: at(1))
        XCTAssertTrue(tracker.update([file("notes.txt", 5)], now: at(2)).isEmpty)
    }

    func testAnEmptyFinalFileIsNotFinished() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.zip.part", 100)], now: at(1))
        XCTAssertTrue(tracker.update([file("a.zip", 0)], now: at(2)).isEmpty)
    }

    func testAnUnnamedChromeDownloadFinishesIntoANewFileWithAnyExtension() {
        var tracker = DownloadTracker()
        _ = tracker.update([file("old.pdf", 3)], now: at(0))
        _ = tracker.update([file("old.pdf", 3), file("Unconfirmed 7.crdownload", 10)], now: at(1))
        XCTAssertEqual(
            tracker.update([file("old.pdf", 3), file("data.csv", 80)], now: at(2)).map(\.name), ["data.csv"])
    }

    func testACancelledUnconfirmedDownloadIgnoresASmallerFileThatAppears() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("Unconfirmed 9.crdownload", 5_000)], now: at(1))
        XCTAssertTrue(tracker.update([file("notes.txt", 20)], now: at(2)).isEmpty)
    }

    func testANamedChromeDownloadOnlyFinishesUnderItsOwnName() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("big.zip.crdownload", 100)], now: at(1))
        XCTAssertTrue(tracker.update([file("other.zip", 500)], now: at(2)).isEmpty)
    }

    func testFinalFileMustBeInTheSameFolder() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("a.zip.part", 100)], now: at(1))
        XCTAssertTrue(tracker.update([file("a.zip", 100, in: "/Users/test/Desktop")], now: at(2)).isEmpty)
    }

    func testALeftoverThatFinishesWithoutGrowingIsNotAnnounced() {
        var tracker = DownloadTracker()
        _ = tracker.update([file("old.zip.crdownload", 100)], now: at(0))
        XCTAssertTrue(tracker.update([file("old.zip", 100)], now: at(1)).isEmpty)
    }

    func testOrdinaryFilesAreNotTracked() {
        var tracker = DownloadTracker()
        _ = tracker.update([], now: at(0))
        _ = tracker.update([file("photo.jpg", 100)], now: at(1))
        _ = tracker.update([file("photo.jpg", 200)], now: at(2))
        XCTAssertNil(tracker.summary(now: at(2)))
    }

    // MARK: Text

    func testByteText() {
        XCTAssertEqual(DownloadText.bytes(0), "0 B")
        XCTAssertEqual(DownloadText.bytes(999), "999 B")
        XCTAssertEqual(DownloadText.bytes(1_500), "1.5 KB")
        XCTAssertEqual(DownloadText.bytes(12_400_000), "12 MB")
        XCTAssertEqual(DownloadText.bytes(3_210_000_000), "3.2 GB")
    }

    func testByteTextMovesUpAUnitInsteadOfShowingAThousand() {
        XCTAssertEqual(DownloadText.bytes(999_499), "999 KB")
        XCTAssertEqual(DownloadText.bytes(999_500), "1.0 MB")
        XCTAssertEqual(DownloadText.bytes(999_999_999), "1.0 GB")
    }

    func testDetailPrefersStalledThenPercentThenRateThenBytes() {
        func progress(received: Int64 = 1_000, total: Int64? = nil, rate: Double? = nil, stalled: Bool = false)
            -> DownloadProgress
        {
            DownloadProgress(
                id: "x", name: "x", received: received, total: total, bytesPerSecond: rate, isStalled: stalled)
        }
        XCTAssertEqual(DownloadText.detail(progress(total: 4_000, stalled: true)), "Stalled")
        XCTAssertEqual(DownloadText.detail(progress(total: 4_000, rate: 10)), "25%")
        XCTAssertEqual(DownloadText.detail(progress(rate: 2_500_000)), "2.5 MB/s")
        XCTAssertEqual(DownloadText.detail(progress(received: 12_000_000)), "12 MB")
    }

    // MARK: Safari bundle info

    func testReadsTheTotalFromASafariBundleInfoPlist() throws {
        let plist: [String: Any] = [
            "DownloadEntryProgressBytesSoFar": 1_024, "DownloadEntryProgressTotalToLoad": 8_192,
            "DownloadEntryURL": "https://example.com/file.zip",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        XCTAssertEqual(SafariDownloadInfo.total(from: data), 8_192)
    }

    func testUnknownOrMissingSafariTotalsAreNil() throws {
        let unknown = try PropertyListSerialization.data(
            fromPropertyList: ["DownloadEntryProgressTotalToLoad": -1], format: .xml, options: 0)
        XCTAssertNil(SafariDownloadInfo.total(from: unknown))
        let empty = try PropertyListSerialization.data(fromPropertyList: [String: Int](), format: .xml, options: 0)
        XCTAssertNil(SafariDownloadInfo.total(from: empty))
        XCTAssertNil(SafariDownloadInfo.total(from: Data("not a plist".utf8)))
    }

    // MARK: Folders

    func testWatchedFoldersAlwaysIncludeDownloadsWithoutDuplicates() {
        let folders = DownloadFolders.resolve(
            extra: ["/Users/test/Desktop/", "/Users/test/Downloads", "", "/Users/test/Desktop"], home: "/Users/test")
        XCTAssertEqual(folders, ["/Users/test/Downloads", "/Users/test/Desktop"])
    }
}
