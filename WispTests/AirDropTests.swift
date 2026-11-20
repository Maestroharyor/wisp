import Foundation
import XCTest

@testable import WispCore

final class SystemSendersTests: XCTestCase {
    func testSharingdReadsAsAirDrop() {
        let airDrop = SystemSenders.identity(for: "com.apple.sharingd")
        XCTAssertEqual(airDrop?.displayName, "AirDrop")
        XCTAssertEqual(airDrop?.iconAppID, "com.apple.finder.Open-AirDrop")
        XCTAssertEqual(airDrop?.homeFolder, "Downloads")
    }

    func testOrdinaryAppsHaveNoStandIn() {
        XCTAssertNil(SystemSenders.identity(for: "com.apple.MobileSMS"))
        XCTAssertNil(SystemSenders.identity(for: ""))
    }

    func testAirDropKeepsItsSystemBannerSoItCanBeAccepted() {
        XCTAssertTrue(SystemSenders.keepsSystemBanner(appID: "com.apple.sharingd"))
    }

    func testOrdinaryAppsDontKeepTheirBanner() {
        XCTAssertFalse(SystemSenders.keepsSystemBanner(appID: "com.apple.MobileSMS"))
        XCTAssertFalse(SystemSenders.keepsSystemBanner(appID: "com.tinyspeck.slackmacgap"))
    }
}

final class AirDropFilterTests: XCTestCase {
    func testOnlyFilesBeingReceivedCount() {
        XCTAssertTrue(AirDropFilter.accepts(kind: .file, operation: .receiving))
    }

    func testBrowserDownloadsAndCopiesAreLeftAlone() {
        XCTAssertFalse(AirDropFilter.accepts(kind: .file, operation: .downloading))
        XCTAssertFalse(AirDropFilter.accepts(kind: .file, operation: .copying))
        XCTAssertFalse(AirDropFilter.accepts(kind: .file, operation: nil))
        XCTAssertFalse(AirDropFilter.accepts(kind: nil, operation: .receiving))
    }
}

final class AirDropTrackerTests: XCTestCase {
    private let folder = "/Users/test/Downloads"
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func snap(
        _ id: String, _ completed: Int64, total: Int64? = 1_000, name: String = "photo.heic", finished: Bool = false,
        cancelled: Bool = false
    ) -> AirDropSnapshot {
        AirDropSnapshot(
            id: id, name: name, folder: folder, completed: completed, total: total, isFinished: finished,
            isCancelled: cancelled)
    }

    func testATransferShowsItsFraction() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 250)], now: at(0))
        let summary = tracker.summary(now: at(0))
        XCTAssertEqual(summary?.primary.fraction, 0.25)
        XCTAssertEqual(summary?.primary.name, "photo.heic")
        XCTAssertEqual(summary?.origin, .airDrop)
        XCTAssertEqual(summary?.count, 1)
    }

    func testAnUnknownTotalStaysIndeterminate() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 250, total: nil)], now: at(0))
        XCTAssertNil(tracker.summary(now: at(0))?.primary.fraction)
        _ = tracker.update([snap("a", 250, total: 0)], now: at(1))
        XCTAssertNil(tracker.summary(now: at(1))?.primary.fraction)
    }

    func testTheRateComesFromRecentProgress() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 0, total: 10_000)], now: at(0))
        _ = tracker.update([snap("a", 2_000, total: 10_000)], now: at(2))
        XCTAssertEqual(tracker.summary(now: at(2))?.primary.bytesPerSecond, 1_000)
    }

    func testAFinishedFlagReportsOnce() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 500)], now: at(0))
        let done = tracker.update([snap("a", 1_000, finished: true)], now: at(1))
        XCTAssertEqual(done, [FinishedDownload(folder: folder, name: "photo.heic", size: 1_000, origin: .airDrop)])
        XCTAssertNil(tracker.summary(now: at(1)))
        XCTAssertEqual(tracker.update([snap("a", 1_000, finished: true)], now: at(2)), [])
        XCTAssertEqual(tracker.update([], now: at(3)), [])
    }

    func testACompleteTransferThatIsWithdrawnCountsAsFinished() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 1_000)], now: at(0))
        let done = tracker.update([], now: at(1))
        XCTAssertEqual(done.map(\.name), ["photo.heic"])
        XCTAssertEqual(done.first?.origin, .airDrop)
    }

    func testACancelledTransferGoesWithoutACard() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 400)], now: at(0))
        XCTAssertEqual(tracker.update([snap("a", 400, cancelled: true)], now: at(1)), [])
        XCTAssertNil(tracker.summary(now: at(1)))
        XCTAssertEqual(tracker.update([], now: at(2)), [])
    }

    func testAnUnfinishedTransferThatIsWithdrawnGoesWithoutACard() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 400)], now: at(0))
        XCTAssertEqual(tracker.update([], now: at(1)), [])
        XCTAssertNil(tracker.summary(now: at(1)))
    }

    func testSeveralTransfersShowTheNewestAndACount() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 100, name: "one.jpg")], now: at(0))
        _ = tracker.update([snap("a", 200, name: "one.jpg"), snap("b", 50, name: "two.jpg")], now: at(1))
        let summary = tracker.summary(now: at(1))
        XCTAssertEqual(summary?.primary.name, "two.jpg")
        XCTAssertEqual(summary?.count, 2)
    }

    func testATransferWithNoProgressForAWhileReadsAsStalled() {
        var tracker = AirDropTracker(stallAfter: 30)
        _ = tracker.update([snap("a", 100)], now: at(0))
        _ = tracker.update([snap("a", 100)], now: at(31))
        XCTAssertEqual(tracker.summary(now: at(31))?.primary.isStalled, true)
        XCTAssertTrue(tracker.isWatching)
    }

    func testBrowserDownloadsStillDefaultToTheBrowserOrigin() {
        let done = FinishedDownload(folder: folder, name: "a.zip", size: 1)
        XCTAssertEqual(done.origin, .browser)
        let progress = DownloadProgress(
            id: "a", name: "a.zip", received: 1, total: nil, bytesPerSecond: nil, isStalled: false)
        XCTAssertEqual(DownloadSummary(primary: progress, count: 1).origin, .browser)
    }
}

final class AirDropSlotTests: XCTestCase {
    func testAnAirDropInProgressIsOngoingAndSitsBesideDownloads() {
        XCTAssertFalse(ActivitySlot.airDrop.isDismissable)
        XCTAssertFalse(ActivitySlot.airDrop.canBeBubble)
        XCTAssertGreaterThan(ActivitySlot.airDrop.priority, ActivitySlot.download.priority)
        XCTAssertLessThan(ActivitySlot.airDrop.priority, ActivitySlot.meeting.priority)
    }

    func testAnAirDropPillKeepsTheUsualPage() {
        XCTAssertEqual(PillDestination(slot: .airDrop), .home)
    }
}
