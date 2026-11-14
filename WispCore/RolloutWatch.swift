import Foundation

/// When Wisp follows a Codex session's rollout file live. Codex has no status line, so its
/// context and plan limits only come from `token_count` lines in the rollout; reading them as
/// they're written, rather than at the turn's end, keeps the ring current while it works.
public enum RolloutWatch {
    /// A prompt or request from a Codex session with a rollout starts the watch. A tool event
    /// does only while the session is `running` (Wisp launched mid-turn): Codex's tool hooks run
    /// in the background, so one can arrive after the turn's Stop and must not start it again.
    public static func starts(_ event: AgentEvent, running: Bool) -> Bool {
        guard event.source == .codex, event.transcriptPath?.isEmpty == false else { return false }
        switch event.kind {
        case .userPromptSubmit, .permissionRequest: return true
        case .preToolUse, .postToolUse: return running
        default: return false
        }
    }

    /// The turn is over: the watch stops, and the turn-end read takes what's left.
    public static func stops(_ event: AgentEvent) -> Bool {
        [.stop, .sessionEnd, .interrupt].contains(event.kind)
    }
}

/// Reads at most once per `interval`, however often the file changes: the first change reads
/// at once, later ones wait for the interval to pass, and changes while a read is scheduled
/// ride along with it.
public struct ReadThrottle: Sendable {
    public let interval: TimeInterval
    private var lastRead: Date?
    private var scheduled = false

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Seconds to wait before reading, or nil when a read is already on its way.
    public mutating func request(now: Date) -> TimeInterval? {
        guard !scheduled else { return nil }
        scheduled = true
        guard let lastRead else { return 0 }
        return max(0, interval - now.timeIntervalSince(lastRead))
    }

    public mutating func didRead(now: Date) {
        scheduled = false
        lastRead = now
    }
}

extension TranscriptUsage {
    /// Adds every complete line in `data` and returns the bytes they took. A line still being
    /// written (no newline yet) is left for the next read.
    @discardableResult
    public mutating func add(complete data: Data) -> Int {
        guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return 0 }
        let complete = data[data.startIndex...end]
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            add(line: String(decoding: line, as: UTF8.self))
        }
        return complete.count
    }
}
