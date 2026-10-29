import XCTest

@testable import WispCore

final class CountdownTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    func testRunsPausesAndResumes() {
        var timer = Countdown(duration: 60)
        timer.start(now: start)
        XCTAssertEqual(timer.remaining(now: start.addingTimeInterval(10)), 50)
        timer.pause(now: start.addingTimeInterval(10))
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remaining(now: start.addingTimeInterval(100)), 50)
        timer.start(now: start.addingTimeInterval(100))
        XCTAssertEqual(timer.remaining(now: start.addingTimeInterval(120)), 30)
        XCTAssertEqual(timer.progress(now: start.addingTimeInterval(120)), 0.5)
    }

    func testFinishesAndClampsAtZero() {
        var timer = Countdown(duration: 5)
        timer.start(now: start)
        XCTAssertTrue(timer.isFinished(now: start.addingTimeInterval(6)))
        XCTAssertEqual(timer.remaining(now: start.addingTimeInterval(6)), 0)
        XCTAssertEqual(timer.progress(now: start.addingTimeInterval(6)), 1)
    }

    func testResetClearsProgress() {
        var timer = Countdown(duration: 5)
        timer.start(now: start)
        timer.pause(now: start.addingTimeInterval(2))
        XCTAssertTrue(timer.hasStarted)
        timer.reset()
        XCTAssertFalse(timer.hasStarted)
        XCTAssertEqual(timer.remaining(now: start), 5)
    }

    func testFormat() {
        XCTAssertEqual(Countdown.format(1500), "25:00")
        XCTAssertEqual(Countdown.format(64.2), "1:05")
        XCTAssertEqual(Countdown.format(3900), "1:05:00")
        XCTAssertEqual(Countdown.format(0), "0:00")
    }
}
