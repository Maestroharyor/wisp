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
    /// being written is left for the next read) and the calls that finished in them, in order.
    /// A first line cut short, from a read that started mid-file, doesn't parse and is skipped.
    public mutating func add(complete data: Data) -> (used: Int, finished: [Call]) {
        guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return (0, []) }
        let complete = data[data.startIndex...end]
        var finished: [Call] = []
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            finished += add(line: Data(line))
        }
        return (complete.count, finished)
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
