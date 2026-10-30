import XCTest

@testable import WispCore

final class MeetingLinkTests: XCTestCase {
    func testFindsCallLinksInAnyField() {
        XCTAssertEqual(
            MeetingLink.find(in: [nil, "Room 4", "Join: https://meet.google.com/abc-defg-hij thanks"])?.absoluteString,
            "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(
            MeetingLink.find(in: ["https://us02web.zoom.us/j/123456?pwd=xyz"])?.host, "us02web.zoom.us")
        XCTAssertEqual(
            MeetingLink.find(in: ["<https://teams.microsoft.com/l/meetup-join/19%3a>"])?.host, "teams.microsoft.com")
        XCTAssertEqual(MeetingLink.find(in: ["https://acme.webex.com/meet/bob"])?.host, "acme.webex.com")
    }

    func testIgnoresOtherLinks() {
        XCTAssertNil(MeetingLink.find(in: ["https://example.com/agenda", "Lunch", nil]))
    }
}

final class MeetingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let link = URL(string: "https://meet.google.com/x")

    private func event(_ start: TimeInterval, _ end: TimeInterval, link: URL? = nil, allDay: Bool = false)
        -> MeetingEvent
    {
        MeetingEvent(
            id: "\(start)", title: "Standup", start: now.addingTimeInterval(start), end: now.addingTimeInterval(end),
            isAllDay: allDay, link: link)
    }

    func testCurrentIsTheTimedEventInProgress() {
        let events = [event(-600, 600, allDay: true), event(-300, 1_200), event(600, 1_200)]
        XCTAssertEqual(Meetings.current(events, now: now)?.start, now.addingTimeInterval(-300))
        XCTAssertNil(Meetings.current([event(60, 600)], now: now))
    }

    func testUpcomingNeedsALinkAndTheWindow() {
        XCTAssertEqual(Meetings.upcoming([event(90, 900, link: link)], now: now, within: 120)?.title, "Standup")
        XCTAssertNil(Meetings.upcoming([event(90, 900)], now: now, within: 120))
        XCTAssertNil(Meetings.upcoming([event(300, 900, link: link)], now: now, within: 120))
        XCTAssertNil(Meetings.upcoming([event(-30, 900, link: link)], now: now, within: 120))
    }
}
