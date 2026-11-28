import Foundation

/// Finds a video-call link (Zoom, Google Meet, Teams, Webex) in an event's fields.
public enum MeetingLink {
    private static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]

    public static func find(in fields: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for field in fields.compactMap({ $0 }) {
            let range = NSRange(field.startIndex..., in: field)
            for match in detector.matches(in: field, range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}

/// The parts of a calendar event the meeting pill needs.
public struct MeetingEvent: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let link: URL?
    /// Declined, cancelled or marked free: on the calendar, but not somewhere the user is.
    public let isFree: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, link: URL?, isFree: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.link = link
        self.isFree = isFree
    }
}

public enum Meetings {
    /// Every occurrence of a recurring event shares one calendar id; the start tells them apart.
    public static func occurrenceID(eventID: String, start: Date) -> String {
        "\(eventID)@\(Int(start.timeIntervalSince1970))"
    }

    /// Longer than this, an event is a block of time (a workday, a course), not a call.
    static let longestMeeting: TimeInterval = 4 * 3_600
    /// How far from an event's start the mic may go live for a call without a link to be it.
    static let joinWindow: TimeInterval = 15 * 60

    /// The meeting happening now, to name a call while the microphone is live (`micSince`).
    /// Only a timed event the user is in, of meeting length. One with a call link counts
    /// whenever the mic is on; any other only when the mic went live near its start, so a
    /// recording in the middle of a calendar block isn't taken for that block's call.
    public static func current(_ events: [MeetingEvent], now: Date, micSince: Date?) -> MeetingEvent? {
        events.filter { event in
            guard !event.isAllDay, !event.isFree, event.start <= now, now < event.end,
                event.end.timeIntervalSince(event.start) <= longestMeeting
            else { return false }
            if event.link != nil { return true }
            guard let micSince else { return false }
            return abs(micSince.timeIntervalSince(event.start)) <= joinWindow
        }
        .max { $0.start < $1.start }
    }

    /// The next event with a call link that starts within `within` seconds.
    public static func upcoming(_ events: [MeetingEvent], now: Date, within: TimeInterval) -> MeetingEvent? {
        events.filter { !$0.isAllDay && $0.link != nil && $0.start > now && $0.start.timeIntervalSince(now) <= within }
            .min { $0.start < $1.start }
    }
}
