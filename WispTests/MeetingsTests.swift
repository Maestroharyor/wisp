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

    private func event(
        _ start: TimeInterval, _ end: TimeInterval, link: URL? = nil, allDay: Bool = false, free: Bool = false
    ) -> MeetingEvent {
        MeetingEvent(
            id: "\(start)", title: "Standup", start: now.addingTimeInterval(start), end: now.addingTimeInterval(end),
            isAllDay: allDay, link: link, isFree: free)
    }

    func testCurrentIsTheTimedEventInProgress() {
        let events = [event(-600, 600, allDay: true), event(-300, 1_200), event(600, 1_200)]
        let micSince = now.addingTimeInterval(-240)
        XCTAssertEqual(Meetings.current(events, now: now, micSince: micSince)?.start, now.addingTimeInterval(-300))
        XCTAssertNil(Meetings.current([event(60, 600)], now: now, micSince: micSince))
    }

    func testDeclinedCancelledAndFreeEventsAreNotMeetings() {
        XCTAssertNil(Meetings.current([event(-300, 600, link: link, free: true)], now: now, micSince: now))
    }

    func testEventsLongerThanFourHoursAreNotMeetings() {
        let workday = event(-3_600, 6 * 3_600, link: link)
        XCTAssertNil(Meetings.current([workday], now: now, micSince: now.addingTimeInterval(-3_500)))
    }

    func testAnEventWithoutALinkNeedsTheMicToStartNearIt() {
        let block = event(-7_200, 3_600)
        XCTAssertNil(Meetings.current([block], now: now, micSince: now), "mic started two hours in")
        XCTAssertNotNil(Meetings.current([block], now: now, micSince: now.addingTimeInterval(-7_200 - 300)))
        XCTAssertNil(Meetings.current([block], now: now, micSince: nil))
    }

    func testAnEventWithACallLinkCountsWheneverTheMicIsOn() {
        let call = event(-7_200, 3_600, link: link)
        XCTAssertNotNil(Meetings.current([call], now: now, micSince: now))
    }

    func testUpcomingNeedsALinkAndTheWindow() {
        XCTAssertEqual(Meetings.upcoming([event(90, 900, link: link)], now: now, within: 120)?.title, "Standup")
        XCTAssertNil(Meetings.upcoming([event(90, 900)], now: now, within: 120))
        XCTAssertNil(Meetings.upcoming([event(300, 900, link: link)], now: now, within: 120))
        XCTAssertNil(Meetings.upcoming([event(-30, 900, link: link)], now: now, within: 120))
    }

    func testOccurrencesOfOneEventGetTheirOwnIDs() {
        let monday = Meetings.occurrenceID(eventID: "E1", start: now)
        let tuesday = Meetings.occurrenceID(eventID: "E1", start: now.addingTimeInterval(86_400))
        XCTAssertNotEqual(monday, tuesday)
        XCTAssertEqual(monday, Meetings.occurrenceID(eventID: "E1", start: now))
    }
}
