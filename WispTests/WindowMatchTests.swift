import XCTest

@testable import WispCore

final class WindowMatchTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 80, width: 800, height: 600)

    func testTheSameTitleIsTheSameWindow() {
        let window = WindowSummary(title: "Report", isMinimised: false)
        let candidates = [
            CapturableWindow(id: 1, title: "Inbox", frame: frame),
            CapturableWindow(id: 2, title: " Report ", frame: .zero),
        ]
        XCTAssertEqual(WindowMatch.best(for: window, in: candidates), 2)
    }

    func testSharedTitlesAreToldApartByFrame() {
        let window = WindowSummary(title: "Untitled", isMinimised: false, frame: frame)
        let candidates = [
            CapturableWindow(id: 1, title: "Untitled", frame: frame.offsetBy(dx: 300, dy: 0)),
            CapturableWindow(id: 2, title: "Untitled", frame: frame.offsetBy(dx: 2, dy: 1)),
        ]
        XCTAssertEqual(WindowMatch.best(for: window, in: candidates), 2)
    }

    func testAnUntitledWindowNeedsAlmostTheSameFrame() {
        let window = WindowSummary(title: nil, isMinimised: false, frame: frame)
        XCTAssertEqual(
            WindowMatch.best(
                for: window, in: [CapturableWindow(id: 7, title: nil, frame: frame.insetBy(dx: 1, dy: 1))]),
            7)
        XCTAssertNil(
            WindowMatch.best(
                for: window, in: [CapturableWindow(id: 7, title: nil, frame: frame.offsetBy(dx: 40, dy: 0))]))
    }

    func testMinimisedOrUnknownWindowsHaveNoPreview() {
        let minimised = WindowSummary(title: "Report", isMinimised: true)
        XCTAssertNil(WindowMatch.best(for: minimised, in: [CapturableWindow(id: 1, title: "Report", frame: frame)]))
        XCTAssertNil(WindowMatch.best(for: WindowSummary(title: "Report", isMinimised: false), in: []))
        XCTAssertNil(
            WindowMatch.best(
                for: WindowSummary(title: nil, isMinimised: false),
                in: [CapturableWindow(id: 1, title: nil, frame: frame)]))
    }

    func testPreviewsKeepTheWindowsShape() {
        XCTAssertEqual(
            WindowPreview.size(for: CGSize(width: 1600, height: 900), fitting: 160), CGSize(width: 160, height: 90))
        XCTAssertEqual(
            WindowPreview.size(for: CGSize(width: 400, height: 800), fitting: 160), CGSize(width: 80, height: 160))
        XCTAssertEqual(WindowPreview.size(for: .zero, fitting: 160), .zero)
    }

    func testTheBadgeOnlyCountsSeveralWindows() {
        XCTAssertNil(AppWindows.badge(count: 0))
        XCTAssertNil(AppWindows.badge(count: 1))
        XCTAssertEqual(AppWindows.badge(count: 3), "3")
        XCTAssertEqual(AppWindows.badge(count: 12), "9+")
    }
}
