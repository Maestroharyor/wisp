import Foundation

/// Follows a Claude Code transcript (JSON lines) for tool calls that got their result.
///
/// Claude Code runs the PermissionRequest hook beside its own prompt and doesn't stop it when
/// the prompt is answered in the terminal: the hook runs on until its timeout. The transcript
/// is where the answer shows: the call's result once it ran, or an error result when it was
/// refused. Calls are remembered from their `tool_use` block and reported when a `tool_result`
/// names them. Subagent lines (`isSidechain`) are left out, since requests are matched against
/// the main agent only.
public struct TranscriptCalls: Sendable {
    public struct Call: Equatable, Sendable {
        public let tool: String
        public let input: JSONValue?

        public init(tool: String, input: JSONValue?) {
            self.tool = tool
            self.input = input
        }
    }

    /// Calls seen without a result yet, by tool use id.
    private var open: [String: Call] = [:]

    public init() {}

    /// Reads every complete line in `data`. Returns the bytes those lines took (a line still
    /// being written is left for the next read), the calls that finished in them, in order, and
    /// for each where its line ends (bytes from the start of `data`, newline included).
    /// A first line cut short, from a read that started mid-file, doesn't parse and is skipped.
    public mutating func add(complete data: Data) -> (used: Int, finished: [Call], ends: [Int]) {
        guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return (0, [], []) }
        let complete = data[data.startIndex...end]
        var finished: [Call] = []
        var ends: [Int] = []
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            let calls = add(line: Data(line))
            let lineEnd = line.endIndex - data.startIndex + 1
            finished += calls
            ends += Array(repeating: lineEnd, count: calls.count)
        }
        return (complete.count, finished, ends)
    }

    /// Whether a call that matches is still waiting for its result.
    public func isOpen(where matches: (Call) -> Bool) -> Bool {
        open.values.contains(where: matches)
    }

    /// The main agent started a subagent (Task, or Agent in newer versions) that hasn't returned.
    public var subagentRunning: Bool { isOpen { ["Task", "Agent"].contains($0.tool) } }

    /// The bytes the first read looks back from the end of a transcript, widening when the
    /// waiting call's `tool_use` isn't in the window (a long result written just before it).
    static let lookBacks: [UInt64] = [1 << 20, 8 << 20, 32 << 20]

    /// Where each try of the first read starts in a transcript of `size` bytes, nearest first.
    /// It stops at the start of the file, so a small file is read once and the cost is bounded.
    public static func lookBackStarts(size: UInt64) -> [UInt64] {
        var starts: [UInt64] = []
        for back in lookBacks {
            let start = size > back ? size - back : 0
            starts.append(start)
            if start == 0 { break }
        }
        return starts
    }

    private mutating func add(line: Data) -> [Call] {
        // Most lines hold neither; skip them before paying for a JSON parse.
        guard line.range(of: Data("tool_".utf8)) != nil,
            let json = try? JSONDecoder().decode(JSONValue.self, from: line),
            json["isSidechain"] != .bool(true),
            case .array(let blocks) = json["message"]?["content"]
        else { return [] }
        // Only the messages themselves: Claude Code also logs copies of its API requests, which
        // repeat earlier calls and results.
        let type = json["type"]?.stringValue
        var finished: [Call] = []
        for block in blocks {
            switch block["type"]?.stringValue {
            case "tool_use" where type == "assistant":
                if let id = block["id"]?.stringValue, let tool = block["name"]?.stringValue {
                    open[id] = Call(tool: tool, input: block["input"])
                }
            case "tool_result" where type == "user":
                if let id = block["tool_use_id"]?.stringValue, let call = open.removeValue(forKey: id) {
                    finished.append(call)
                }
            default:
                break
            }
        }
        return finished
    }
}
