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

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, link: URL?) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.link = link
    }
}

public enum Meetings {
    /// The timed event happening now, to name a call while the microphone is live.
    public static func current(_ events: [MeetingEvent], now: Date) -> MeetingEvent? {
        events.filter { !$0.isAllDay && $0.start <= now && now < $0.end }.max { $0.start < $1.start }
    }

    /// The next event with a call link that starts within `within` seconds.
    public static func upcoming(_ events: [MeetingEvent], now: Date, within: TimeInterval) -> MeetingEvent? {
        events.filter { !$0.isAllDay && $0.link != nil && $0.start > now && $0.start.timeIntervalSince(now) <= within }
            .min { $0.start < $1.start }
    }
}
