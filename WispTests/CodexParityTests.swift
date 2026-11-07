import XCTest

@testable import WispCore

/// Codex rollout lines, built by hand from the shape of real rollouts (keys and event types
/// only) with made-up values.
final class CodexRolloutTests: XCTestCase {
    private let turnContext =
        #"{"timestamp":"2026-11-07T10:00:00.000Z","type":"turn_context","payload":{"cwd":"/w","approval_policy":"on-request","sandbox_policy":{"type":"workspace-write"},"model":"gpt-5.3-codex","effort":"medium","summary":"auto"}}"#

    private func tokenCount(
        total: Int = 51_000, window: Int = 258_400, input: Int = 1_000_000, cached: Int = 400_000,
        output: Int = 100_000, limits: String? = nil
    ) -> String {
        let rateLimits = limits.map { #","rate_limits":\#($0)"# } ?? ""
        return
            #"{"timestamp":"2026-11-07T10:00:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)},"last_token_usage":{"input_tokens":\#(total - 1000),"cached_input_tokens":0,"output_tokens":1000,"reasoning_output_tokens":0,"total_tokens":\#(total)},"model_context_window":\#(window)}\#(rateLimits)}}"#
    }

    func testContextIsTheLastRequestOverTheModelWindow() throws {
        var usage = TranscriptUsage()
        usage.add(lines: [turnContext, tokenCount(total: 129_200, window: 258_400)])
        XCTAssertEqual(try XCTUnwrap(usage.contextPercent), 50, accuracy: 1e-9)
    }

    func testContextNeedsAWindow() {
        var usage = TranscriptUsage()
        usage.add(line: tokenCount(window: 0))
        XCTAssertNil(usage.contextPercent)
    }

    func testTheModelComesFromTheTurnContext() {
        var usage = TranscriptUsage()
        usage.add(line: turnContext)
        XCTAssertEqual(usage.lastModel, "gpt-5.3-codex")
    }

    func testCodexCostUsesOpenAIPrices() throws {
        var usage = TranscriptUsage()
        usage.add(lines: [turnContext, tokenCount(input: 1_000_000, cached: 400_000, output: 100_000)])
        // gpt-5.3-codex: 600k fresh input at $1.75, 400k cached at $0.175, 100k out at $14.
        XCTAssertEqual(try XCTUnwrap(usage.cost()), 0.6 * 1.75 + 0.4 * 0.175 + 0.1 * 14, accuracy: 1e-9)
    }

    func testRateLimitsWithResetTimes() {
        var usage = TranscriptUsage()
        usage.add(
            line: tokenCount(
                limits:
                    #"{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1800003600},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1800300000}}"#
            ))
        XCTAssertEqual(
            usage.limits,
            [
                UsageReading(
                    window: .fiveHour, percent: 12.5, resets: Date(timeIntervalSince1970: 1_800_003_600),
                    source: .codex),
                UsageReading(
                    window: .sevenDay, percent: 40, resets: Date(timeIntervalSince1970: 1_800_300_000), source: .codex),
            ])
    }

    func testOlderRolloutsCountDownFromTheLine() throws {
        var usage = TranscriptUsage()
        usage.add(
            line: tokenCount(
                limits:
                    #"{"primary":{"used_percent":5,"window_minutes":300,"resets_in_seconds":600},"secondary":{"used_percent":1,"window_minutes":4321,"resets_in_seconds":60}}"#
            ))
        let stamp = Date(timeIntervalSince1970: 1_794_045_605)
        XCTAssertEqual(CodexRollout.date("2026-11-07T10:00:05.000Z"), stamp)
        XCTAssertEqual(CodexRollout.date("2026-11-07T10:00:05Z"), stamp)
        XCTAssertEqual(
            usage.limits, [UsageReading(window: .fiveHour, percent: 5, resets: stamp + 600, source: .codex)],
            "a window Wisp has no name for is left out")
    }

    func testALineWithOnlyRateLimitsStillCounts() {
        var usage = TranscriptUsage()
        usage.add(
            line:
                #"{"timestamp":"2026-11-07T10:00:05.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":3,"window_minutes":300,"resets_at":1800003600}}}}"#
        )
        XCTAssertEqual(usage.limits.map(\.percent), [3])
        XCTAssertEqual(usage.total, TokenUsage())
    }
}

final class OpenAIPricingTests: XCTestCase {
    func testLongestPrefixWins() {
        XCTAssertEqual(ModelPricing.price(for: "gpt-5")?.input, 1.25)
        XCTAssertEqual(ModelPricing.price(for: "gpt-5-mini")?.input, 0.25)
        XCTAssertEqual(ModelPricing.price(for: "gpt-5.4-mini")?.output, 4.5)
        XCTAssertEqual(ModelPricing.price(for: "gpt-5.5-pro")?.input, 30)
        XCTAssertEqual(ModelPricing.price(for: "gpt-6.1-sol")?.cacheRead, 0.1)
    }

    func testCodexVariantsUseTheirBaseModel() {
        XCTAssertEqual(ModelPricing.price(for: "gpt-5.3-codex")?.input, 1.75)
        XCTAssertEqual(ModelPricing.price(for: "gpt-5.1-codex-max")?.input, 1.25)
        XCTAssertEqual(ModelPricing.price(for: "gpt-5.2-codex")?.output, 14)
    }
}

final class LimitsPerAgentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testEachAgentsWindowsAreWatchedApart() {
        var watch = LimitWatch()
        let resets = start + 3600
        let claude = UsageReading(window: .fiveHour, percent: 85, resets: resets)
        let codex = UsageReading(window: .fiveHour, percent: 85, resets: resets, source: .codex)
        XCTAssertEqual(watch.record([claude], at: start).count, 1)
        let due = watch.record([codex], at: start)
        XCTAssertEqual(due.map(\.text), ["Codex 5 h limit 85%"])
    }

    func testMergeReplacesOnlyThatAgentsReadings() {
        let claude = UsageReading(window: .fiveHour, percent: 10, resets: nil)
        let oldCodex = UsageReading(window: .fiveHour, percent: 1, resets: nil, source: .codex)
        let newCodex = UsageReading(window: .sevenDay, percent: 2, resets: nil, source: .codex)
        XCTAssertEqual(UsageLimits.merge([oldCodex, claude], with: [newCodex]), [claude, newCodex])
    }

    func testTheReportNamesOtherAgents() throws {
        let limit = AgentReport.Limit(window: "fiveHour", percent: 50, resets: nil, full: nil, agent: "Codex")
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(limit))
        XCTAssertEqual(json["agent"], .string("Codex"))
        XCTAssertEqual(AgentCLI.limitsLine([limit]), "Limits  Codex 5 h 50%")
        let claude = AgentReport.Limit(window: "fiveHour", percent: 50, resets: nil, full: nil)
        XCTAssertEqual(AgentCLI.limitsLine([claude]), "Limits  5 h 50%")
    }

    func testCodexSessionsTakeTheirContextFromTheTranscript() throws {
        var sessions = AgentSessions()
        sessions.apply(
            try AgentEvent.decode(Data(#"{"session_id":"c","hook_event_name":"Stop","wisp_source":"codex"}"#.utf8)),
            at: start)
        XCTAssertTrue(sessions.setContextPercent(42, session: "c"))
        XCTAssertFalse(sessions.setContextPercent(42.2, session: "c"), "the pill shows whole numbers")
        XCTAssertEqual(sessions.session("c")?.contextPercent, 42.2)
    }
}
