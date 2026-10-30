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

    private static func compact(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count)"
        case ..<1_000_000: "\(Int((Double(count) / 1_000).rounded()))k"
        default: String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }
}

/// Reads an agent's transcript (JSON lines) for token usage.
///
/// Claude Code logs one line per content block, each repeating its message's usage, so
/// messages are counted once by id. Codex logs running totals in `token_count` events;
/// the latest one wins. Its cached input is part of its input count, so it is split out.
public struct TranscriptUsage: Sendable {
    private var byModel: [String: TokenUsage] = [:]
    private var seen: Set<String> = []
    private var codexTotal: TokenUsage?

    public init() {}

    public var total: TokenUsage {
        byModel.values.reduce(codexTotal ?? TokenUsage(), +)
    }

    public mutating func add(lines: [String]) {
        for line in lines { add(line: line) }
    }

    public mutating func add(line: String) {
        guard line.contains("usage"), let json = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        else { return }
        if let message = json["message"], let usage = message["usage"] {
            let id = message["id"]?.stringValue ?? UUID().uuidString
            guard seen.insert(id).inserted else { return }
            let model = message["model"]?.stringValue ?? "unknown"
            byModel[model, default: TokenUsage()] =
                byModel[model, default: TokenUsage()]
                + TokenUsage(
                    input: usage["input_tokens"]?.intValue ?? 0,
                    output: usage["output_tokens"]?.intValue ?? 0,
                    cacheWrite: usage["cache_creation_input_tokens"]?.intValue ?? 0,
                    cacheRead: usage["cache_read_input_tokens"]?.intValue ?? 0)
        } else if json["payload"]?["type"]?.stringValue == "token_count",
            let usage = json["payload"]?["info"]?["total_token_usage"]
        {
            let cached = usage["cached_input_tokens"]?.intValue ?? 0
            codexTotal = TokenUsage(
                input: max(0, (usage["input_tokens"]?.intValue ?? 0) - cached),
                output: usage["output_tokens"]?.intValue ?? 0,
                cacheRead: cached)
        }
    }

    /// Estimated dollars, or nil when any of the tokens came from a model without a price.
    public func cost() -> Double? {
        guard codexTotal == nil, !byModel.isEmpty else { return nil }
        var total = 0.0
        for (model, usage) in byModel {
            guard let price = ModelPricing.price(for: model) else { return nil }
            total += price.cost(usage)
        }
        return total
    }
}

/// Anthropic list prices in dollars per million tokens (from the Claude API model table,
/// October 2026). A five-minute cache write costs 1.25× input.
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

    /// Model id prefixes, longest first so "claude-opus-5-5" wins over "claude-opus-5".
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
    ]

    public static func price(for model: String) -> Price? {
        table.first { model.hasPrefix($0.prefix) }?.price
    }
}
