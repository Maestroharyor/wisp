import Foundation

/// What Claude Code passes on stdin to its `statusLine` command each time the session
/// changes. Every field is optional: older versions send fewer, and the context window
/// figures are null early in a session and right after `/compact`.
public struct StatusLineSnapshot: Equatable, Sendable {
    public var sessionID: String?
    /// The working folder's full path.
    public var cwd: String
    public var transcriptPath: String?
    public var model: String?
    /// The session's cost in dollars, as Claude Code reports it.
    public var cost: Double?
    public var duration: TimeInterval?
    public var apiDuration: TimeInterval?
    public var linesAdded: Int?
    public var linesRemoved: Int?
    /// Share of the context window the latest request used, 0 to 100.
    public var contextPercent: Double?
    public var contextSize: Int?
    /// Set only for sessions running in a Claude Code worktree.
    public var branch: String?
    /// Everything else Claude Code reports, for the session's details.
    public var extras = Extras()

    public struct Extras: Equatable, Sendable {
        public var sessionName: String?
        public var version: String?
        public var outputStyle: String?
        public var effort: String?
        public var thinking: Bool?
        public var fastMode: Bool?
        public var inputTokens: Int?
        public var outputTokens: Int?
        /// Tokens in the latest request: input plus cache reads and writes.
        public var contextTokens: Int?
        /// Subscription usage, 0 to 100, in the current five-hour and seven-day windows.
        public var fiveHourPercent: Double?
        public var sevenDayPercent: Double?
        public var cacheHitRatio: Double?
        public var pullRequest: Int?
        public var pullRequestState: String?

        public init() {}

        init(json: JSONValue) {
            sessionName = json["session_name"]?.stringValue
            version = json["version"]?.stringValue
            outputStyle = json["output_style"]?["name"]?.stringValue
            effort = json["effort"]?["level"]?.stringValue
            thinking = json["thinking"]?["enabled"].flatMap(Self.bool)
            fastMode = json["fast_mode"].flatMap(Self.bool)
            let context = json["context_window"]
            inputTokens = context?["total_input_tokens"]?.intValue
            outputTokens = context?["total_output_tokens"]?.intValue
            if let usage = context?["current_usage"], case .object = usage {
                contextTokens =
                    (usage["input_tokens"]?.intValue ?? 0) + (usage["cache_read_input_tokens"]?.intValue ?? 0)
                    + (usage["cache_creation_input_tokens"]?.intValue ?? 0)
            }
            fiveHourPercent = json["rate_limits"]?["five_hour"]?["used_percentage"]?.doubleValue
            sevenDayPercent = json["rate_limits"]?["seven_day"]?["used_percentage"]?.doubleValue
            cacheHitRatio = json["prompt_cache"]?["hit_ratio"]?.doubleValue
            pullRequest = json["pr"]?["number"]?.intValue
            pullRequestState = json["pr"]?["review_state"]?.stringValue
        }

        private static func bool(_ value: JSONValue) -> Bool? {
            if case .bool(let flag) = value { return flag }
            return nil
        }
    }

    public init(
        sessionID: String? = nil, cwd: String = "", transcriptPath: String? = nil, model: String? = nil,
        cost: Double? = nil, duration: TimeInterval? = nil, apiDuration: TimeInterval? = nil,
        linesAdded: Int? = nil, linesRemoved: Int? = nil, contextPercent: Double? = nil, contextSize: Int? = nil,
        branch: String? = nil
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.cost = cost
        self.duration = duration
        self.apiDuration = apiDuration
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.contextPercent = contextPercent
        self.contextSize = contextSize
        self.branch = branch
    }

    public init(json: JSONValue) {
        let cost = json["cost"]
        let context = json["context_window"]
        self.init(
            sessionID: json["session_id"]?.stringValue,
            cwd: json["workspace"]?["current_dir"]?.stringValue ?? json["cwd"]?.stringValue ?? "",
            transcriptPath: json["transcript_path"]?.stringValue,
            model: json["model"]?["display_name"]?.stringValue ?? json["model"]?["id"]?.stringValue,
            cost: cost?["total_cost_usd"]?.doubleValue,
            duration: cost?["total_duration_ms"]?.doubleValue.map { $0 / 1000 },
            apiDuration: cost?["total_api_duration_ms"]?.doubleValue.map { $0 / 1000 },
            linesAdded: cost?["total_lines_added"]?.intValue,
            linesRemoved: cost?["total_lines_removed"]?.intValue,
            contextPercent: context?["used_percentage"]?.doubleValue.map { min(max($0, 0), 100) },
            contextSize: context?["context_window_size"]?.intValue,
            branch: json["worktree"]?["branch"]?.stringValue
        )
        extras = Extras(json: json)
    }

    /// Input that isn't JSON gives an empty snapshot, so the bar still prints something.
    public static func decode(_ data: Data) -> StatusLineSnapshot {
        (try? JSONDecoder().decode(JSONValue.self, from: data)).map(StatusLineSnapshot.init(json:))
            ?? StatusLineSnapshot()
    }

    public var project: String { AgentEvent.projectName(cwd: cwd, source: .claude) }
}
