import Foundation

/// One line of an edit's diff.
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case context
        case removed
        case added
    }

    public let kind: Kind
    public let text: String
}

/// What an approval card can show before you allow a request: an edit's changed lines, the
/// start of a new file, a whole command or the plan. `more` counts lines left out.
public enum ApprovalPreview: Equatable, Sendable {
    case diff([DiffLine], more: Int)
    case text(String, more: Int)
    case markdown(String)

    /// Lines of unchanged code kept around an edit's changes.
    static let contextLines = 1

    /// The preview for a request, at most `limit` lines; nil when there's nothing more to
    /// see than the card's summary.
    public static func make(tool: String, input: JSONValue?, limit: Int) -> ApprovalPreview? {
        switch tool {
        case "Edit":
            guard let old = input?["old_string"]?.stringValue, let new = input?["new_string"]?.stringValue else {
                return nil
            }
            let lines = diff(old: old, new: new)
            guard !lines.isEmpty else { return nil }
            return .diff(Array(lines.prefix(limit)), more: max(0, lines.count - limit))
        case "Write":
            return capped(input?["content"]?.stringValue, limit: limit)
        case "Bash":
            return capped(input?["command"]?.stringValue, limit: .max)
        case "ExitPlanMode":
            guard let plan = input?["plan"]?.stringValue, !plan.trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }
            return .markdown(plan)
        default:
            return nil
        }
    }

    private static func capped(_ text: String?, limit: Int) -> ApprovalPreview? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lines = text.components(separatedBy: "\n")
        return .text(lines.prefix(limit).joined(separator: "\n"), more: max(0, lines.count - limit))
    }

    /// The changed middle of an edit: lines both sides share at the start and end are
    /// dropped, keeping `contextLines` of them on each side.
    static func diff(old: String, new: String) -> [DiffLine] {
        let before = old.components(separatedBy: "\n")
        let after = new.components(separatedBy: "\n")
        var head = 0
        while head < before.count, head < after.count, before[head] == after[head] { head += 1 }
        var tail = 0
        while tail < before.count - head, tail < after.count - head,
            before[before.count - 1 - tail] == after[after.count - 1 - tail]
        {
            tail += 1
        }
        let leading = before[max(0, head - contextLines)..<head].map { DiffLine(kind: .context, text: $0) }
        let removed = before[head..<(before.count - tail)].map { DiffLine(kind: .removed, text: $0) }
        let added = after[head..<(after.count - tail)].map { DiffLine(kind: .added, text: $0) }
        let trailingEnd = min(before.count, before.count - tail + contextLines)
        let trailing = before[(before.count - tail)..<trailingEnd].map { DiffLine(kind: .context, text: $0) }
        guard !removed.isEmpty || !added.isEmpty else { return [] }
        return leading + removed + added + trailing
    }
}
