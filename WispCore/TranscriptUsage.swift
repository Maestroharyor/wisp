import Foundation

/// Token counts for one agent session.
public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public var all: Int { input + output + cacheWrite + cacheRead }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite, cacheRead: lhs.cacheRead + rhs.cacheRead)
    }

    /// "182k tokens · ~$0.41", or just the tokens when the cost is unknown.
    public func summary(cost: Double?) -> String {
        let tokens = "\(Self.compact(all)) tokens"
        guard let cost else { return tokens }
        return tokens + String(format: " · ~$%.2f", cost)
    }

    static func compact(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count)"
        // Below 999,500 so rounding never shows "1000k".
        case ..<999_500: "\(Int((Double(count) / 1_000).rounded()))k"
        default: String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }
}

/// Reads an agent's transcript (JSON lines) for token usage.
///
/// Claude Code logs one line per content block, each repeating its message's usage, so
/// messages are counted once by id. Codex's rollout logs running totals in `token_count`
/// events; the latest one wins. Its cached input is part of its input count, so it is split
/// out. The same events carry Codex's context window and plan limits, which it has no status
/// line to report.
public struct TranscriptUsage: Sendable {
    private var byModel: [String: TokenUsage] = [:]
    private var seen: Set<String> = []
    private var codexTotal: TokenUsage?
    /// The model of the newest Claude message, or of the latest Codex turn, as an id
    /// ("claude-opus-4-1-...", "gpt-5.3-codex").
    public private(set) var lastModel: String?
    /// How full Codex's context window was after its latest request, 0 to 100.
    public private(set) var contextPercent: Double?
    /// Codex's plan usage windows from its latest report.
    public private(set) var limits: [UsageReading] = []

    public init() {}

    public var total: TokenUsage {
        byModel.values.reduce(codexTotal ?? TokenUsage(), +)
    }

    public mutating func add(lines: [String]) {
        for line in lines { add(line: line) }
    }

    public mutating func add(line: String) {
        // Most lines are message text; skip them before paying for a JSON parse.
        guard line.contains("usage") || line.contains("rate_limits") || line.contains("turn_context"),
            let json = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        else { return }
        if let message = json["message"], let usage = message["usage"] {
            addClaude(message: message, usage: usage)
        } else if json["type"]?.stringValue == "turn_context" {
            if let model = json["payload"]?["model"]?.stringValue { lastModel = model }
        } else if json["payload"]?["type"]?.stringValue == "token_count", let payload = json["payload"] {
            addCodex(payload, at: json["timestamp"]?.stringValue.flatMap(CodexRollout.date))
        }
    }

    private mutating func addClaude(message: JSONValue, usage: JSONValue) {
        let id = message["id"]?.stringValue ?? UUID().uuidString
        guard seen.insert(id).inserted else { return }
        let model = message["model"]?.stringValue ?? "unknown"
        // Claude Code writes "<synthetic>" for messages no model produced.
        if model.hasPrefix("claude") { lastModel = model }
        byModel[model, default: TokenUsage()] =
            byModel[model, default: TokenUsage()]
            + TokenUsage(
                input: usage["input_tokens"]?.intValue ?? 0,
                output: usage["output_tokens"]?.intValue ?? 0,
                cacheWrite: usage["cache_creation_input_tokens"]?.intValue ?? 0,
                cacheRead: usage["cache_read_input_tokens"]?.intValue ?? 0)
    }

    private mutating func addCodex(_ payload: JSONValue, at timestamp: Date?) {
        if let usage = payload["info"]?["total_token_usage"] {
            let cached = usage["cached_input_tokens"]?.intValue ?? 0
            codexTotal = TokenUsage(
                input: max(0, (usage["input_tokens"]?.intValue ?? 0) - cached),
                output: usage["output_tokens"]?.intValue ?? 0,
                cacheRead: cached)
        }
        if let window = payload["info"]?["model_context_window"]?.doubleValue, window > 0,
            let used = payload["info"]?["last_token_usage"]?["total_tokens"]?.doubleValue
        {
            contextPercent = min(max(used / window * 100, 0), 100)
        }
        let readings = UsageLimits.codexReadings(payload["rate_limits"], at: timestamp)
        if !readings.isEmpty { limits = readings }
    }

    /// Estimated dollars, or nil when any of the tokens came from a model without a price.
    public func cost() -> Double? {
        if let codexTotal {
            guard byModel.isEmpty, let model = lastModel, let price = ModelPricing.price(for: model) else {
                return nil
            }
            return price.cost(codexTotal)
        }
        guard !byModel.isEmpty else { return nil }
        var total = 0.0
        for (model, usage) in byModel {
            guard let price = ModelPricing.price(for: model) else { return nil }
            total += price.cost(usage)
        }
        return total
    }
}

/// Times in a Codex rollout: ISO 8601 in UTC, usually with milliseconds.
public enum CodexRollout {
    public static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// List prices in dollars per million tokens, for estimates when the agent reports no cost
/// itself. Anthropic's from the Claude API model table (October 2026); a five-minute cache
/// write costs 1.25× input. OpenAI's from its API pricing page (standard tier, short context,
/// November 2026). Codex model variants ("gpt-5.1-codex-max") are priced as the base model
/// their id starts with, unless the page lists them.
public enum ModelPricing {
    public struct Price: Equatable, Sendable {
        public let input: Double
        public let output: Double
        public let cacheRead: Double

        public var cacheWrite: Double { input * 1.25 }

        func cost(_ usage: TokenUsage) -> Double {
            (Double(usage.input) * input + Double(usage.output) * output + Double(usage.cacheWrite) * cacheWrite
                + Double(usage.cacheRead) * cacheRead) / 1_000_000
        }
    }

    /// Model id prefixes. The longest match wins, so "gpt-5-mini" isn't priced as "gpt-5".
    static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: 1)),
        ("claude-mythos-5", Price(input: 10, output: 50, cacheRead: 1)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.2)),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.2)),
        ("claude-sonnet-4-6", Price(input: 3, output: 15, cacheRead: 0.3)),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.2)),
        ("claude-haiku-5-5", Price(input: 0.1, output: 0.5, cacheRead: 0.01)),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.1)),
        ("gpt-6-astra", Price(input: 10, output: 50, cacheRead: 1)),
        ("gpt-6.1-sol", Price(input: 2, output: 10, cacheRead: 0.1)),
        ("gpt-6.1-terra", Price(input: 1, output: 5, cacheRead: 0.05)),
        ("gpt-6-sol", Price(input: 2, output: 10, cacheRead: 0.2)),
        ("gpt-6-luna", Price(input: 0.1, output: 0.5, cacheRead: 0.01)),
        ("gpt-5.6-sol", Price(input: 4, output: 20, cacheRead: 0.4)),
        ("gpt-5.6-terra", Price(input: 2, output: 12, cacheRead: 0.2)),
        ("gpt-5.6-luna", Price(input: 0.2, output: 1.2, cacheRead: 0.02)),
        // Pro models list no cached rate: cached input is charged as input.
        ("gpt-5.5-pro", Price(input: 30, output: 180, cacheRead: 30)),
        ("gpt-5.5", Price(input: 5, output: 30, cacheRead: 0.5)),
        ("gpt-5.4-pro", Price(input: 30, output: 180, cacheRead: 30)),
        ("gpt-5.4-mini", Price(input: 0.75, output: 4.5, cacheRead: 0.075)),
        ("gpt-5.4-nano", Price(input: 0.2, output: 1.25, cacheRead: 0.02)),
        ("gpt-5.4", Price(input: 2.5, output: 15, cacheRead: 0.25)),
        ("gpt-5.3-codex", Price(input: 1.75, output: 14, cacheRead: 0.175)),
        ("gpt-5.2-pro", Price(input: 21, output: 168, cacheRead: 21)),
        ("gpt-5.2", Price(input: 1.75, output: 14, cacheRead: 0.175)),
        ("gpt-5.1", Price(input: 1.25, output: 10, cacheRead: 0.125)),
        ("gpt-5-pro", Price(input: 15, output: 120, cacheRead: 15)),
        ("gpt-5-mini", Price(input: 0.25, output: 2, cacheRead: 0.025)),
        ("gpt-5-nano", Price(input: 0.05, output: 0.4, cacheRead: 0.005)),
        ("gpt-5", Price(input: 1.25, output: 10, cacheRead: 0.125)),
    ]

    public static func price(for model: String) -> Price? {
        table.filter { matches(model, prefix: $0.prefix) }.max { $0.prefix.count < $1.prefix.count }?.price
    }

    /// A prefix ends at a word: "gpt-5" covers "gpt-5-codex" but not "gpt-5.7", an unlisted
    /// model that may cost something else.
    private static func matches(_ model: String, prefix: String) -> Bool {
        guard model.hasPrefix(prefix) else { return false }
        guard let next = model.dropFirst(prefix.count).first else { return true }
        return next != "." && !next.isNumber
    }
}
