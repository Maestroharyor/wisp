import Foundation
import XCTest

@testable import WispCore

final class SystemSendersTests: XCTestCase {
    func testSharingdReadsAsAirDrop() {
        let airDrop = SystemSenders.identity(for: "com.apple.sharingd")
        XCTAssertEqual(airDrop?.displayName, "AirDrop")
        XCTAssertEqual(airDrop?.icon, .airDrop)
        XCTAssertEqual(airDrop?.appID, "com.apple.finder.Open-AirDrop")
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

final class AirDropIntakeTests: XCTestCase {
    func testAFileStillWaitingForItsOperationIsPending() {
        XCTAssertEqual(AirDropFilter.classify(kind: .file, operation: nil), .pending)
    }

    func testOtherFileOperationsAreDropped() {
        XCTAssertEqual(AirDropFilter.classify(kind: .file, operation: .downloading), .ignored)
        XCTAssertEqual(AirDropFilter.classify(kind: nil, operation: nil), .ignored)
        XCTAssertEqual(AirDropFilter.classify(kind: .file, operation: .receiving), .receiving)
    }
}

final class AirDropTrackerEdgeTests: XCTestCase {
    private let folder = "/Users/test/Downloads"
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func snap(
        _ id: String, _ completed: Int64, name: String = "a.jpg", finished: Bool = false, old: Bool = false
    ) -> AirDropSnapshot {
        AirDropSnapshot(
            id: id, name: name, folder: folder, completed: completed, total: 100, isFinished: finished,
            isCancelled: false, isOld: old)
    }

    func testATransferThatFinishedBeforeWatchingGetsNoCard() {
        var tracker = AirDropTracker()
        XCTAssertEqual(tracker.update([snap("a", 100, finished: true, old: true)], now: at(0)), [])
        var other = AirDropTracker()
        _ = other.update([snap("b", 100, old: true)], now: at(0))
        XCTAssertEqual(other.update([], now: at(1)), [])
    }

    func testAnOldTransferStillInFlightShowsItsPill() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 40, old: true)], now: at(0))
        XCTAssertEqual(tracker.summary(now: at(0))?.primary.fraction, 0.4)
    }

    func testCompleteButNotYetFinishedWaitsForTheEnd() {
        var tracker = AirDropTracker()
        XCTAssertEqual(tracker.update([snap("a", 100)], now: at(0)), [])
        XCTAssertEqual(tracker.update([], now: at(1)).count, 1)
    }

    func testAnIDThatComesBackAfterSettlingIsANewTransfer() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 50)], now: at(0))
        _ = tracker.update([snap("a", 100, finished: true)], now: at(1))
        _ = tracker.update([], now: at(2))
        _ = tracker.update([snap("a", 10)], now: at(3))
        XCTAssertEqual(tracker.summary(now: at(3))?.primary.received, 10)
    }

    func testDuplicateIDsInOneUpdateKeepTheLast() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 10), snap("a", 30)], now: at(0))
        XCTAssertEqual(tracker.summary(now: at(0))?.count, 1)
        XCTAssertEqual(tracker.summary(now: at(0))?.primary.received, 30)
    }

    func testAStallClearsWhenProgressResumes() {
        var tracker = AirDropTracker(stallAfter: 30)
        _ = tracker.update([snap("a", 10)], now: at(0))
        _ = tracker.update([snap("a", 10)], now: at(31))
        XCTAssertEqual(tracker.summary(now: at(31))?.primary.isStalled, true)
        _ = tracker.update([snap("a", 20)], now: at(32))
        XCTAssertEqual(tracker.summary(now: at(32))?.primary.isStalled, false)
    }

    func testTransfersSeenTogetherPutTheLaterOneFirst() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("9", 10, name: "nine.jpg")], now: at(0))
        _ = tracker.update([snap("9", 10, name: "nine.jpg"), snap("10", 10, name: "ten.jpg")], now: at(0))
        XCTAssertEqual(tracker.summary(now: at(0))?.primary.name, "ten.jpg")
    }

    func testSeveralFinishingAtOnceAreAllReported() {
        var tracker = AirDropTracker()
        _ = tracker.update([snap("a", 50, name: "a.jpg"), snap("b", 50, name: "b.jpg")], now: at(0))
        let done = tracker.update(
            [snap("a", 100, name: "a.jpg", finished: true), snap("b", 100, name: "b.jpg", finished: true)], now: at(1))
        XCTAssertEqual(done.map(\.name), ["a.jpg", "b.jpg"])
    }
}

final class AirDropArrivalsTests: XCTestCase {
    private let folder = "/Users/test/Downloads"

    private func file(_ name: String, _ size: Int64) -> FinishedDownload {
        FinishedDownload(folder: folder, name: name, size: size, origin: .airDrop)
    }

    func testNothingMakesNoCard() {
        XCTAssertNil(AirDropArrivals.combine([]))
    }

    func testOneFileIsItself() {
        XCTAssertEqual(AirDropArrivals.combine([file("a.jpg", 5)]), file("a.jpg", 5))
    }

    func testSeveralFilesMakeOneCardForTheirFolder() {
        let batch = AirDropArrivals.combine([file("a.jpg", 5), file("b.jpg", 7), file("c.jpg", 1)])
        XCTAssertEqual(batch?.name, "3 items")
        XCTAssertEqual(batch?.size, 13)
        XCTAssertEqual(batch?.itemCount, 3)
        XCTAssertEqual(batch?.path, folder)
        XCTAssertEqual(batch?.origin, .airDrop)
    }
}

final class BannerRuleTests: XCTestCase {
    func testCustomActionTitlesAreRead() {
        XCTAssertEqual(BannerRule.title(of: "Name:Accept\nTarget:0x0\nSelector:(null)"), "Accept")
        XCTAssertEqual(BannerRule.title(of: "AXPress"), "AXPress")
    }

    func testABannerWithAcceptAndDeclineStays() {
        let actions = ["AXPress", "Name:Close\nTarget:0x0", "Name:Accept\nTarget:0x0", "Name:Decline\nTarget:0x0"]
        XCTAssertTrue(BannerRule.keepsBanner(actions: actions))
        XCTAssertNil(BannerRule.closeAction(in: actions))
    }

    func testAnOrdinaryBannerCloses() {
        let actions = ["AXPress", "Name:Show Details\nTarget:0x0", "Name:Close\nTarget:0x0"]
        XCTAssertFalse(BannerRule.keepsBanner(actions: actions))
        XCTAssertEqual(BannerRule.closeAction(in: actions), "Name:Close\nTarget:0x0")
    }

    func testABannerWithoutCloseHasNothingToPress() {
        XCTAssertNil(BannerRule.closeAction(in: ["AXPress"]))
    }
}
