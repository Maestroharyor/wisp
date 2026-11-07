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
            return capped(edits([input]), limit: limit)
        case "MultiEdit":
            guard case .array(let list) = input?["edits"] else { return nil }
            return capped(edits(list), limit: limit)
        case "apply_patch":
            guard let patch = input?["command"]?.stringValue else { return nil }
            return capped(patchLines(patch), limit: limit)
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

    private static func capped(_ lines: [DiffLine], limit: Int) -> ApprovalPreview? {
        guard !lines.isEmpty else { return nil }
        return .diff(Array(lines.prefix(limit)), more: max(0, lines.count - limit))
    }

    private static func edits(_ edits: [JSONValue?]) -> [DiffLine] {
        edits.flatMap { edit -> [DiffLine] in
            guard let old = edit?["old_string"]?.stringValue, let new = edit?["new_string"]?.stringValue else {
                return []
            }
            return diff(old: old, new: new)
        }
    }

    /// Codex's patch format: "-" and "+" lines, with file headers and "@@" kept as context.
    static func patchLines(_ patch: String) -> [DiffLine] {
        patch.components(separatedBy: "\n").compactMap { raw in
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line == "*** Begin Patch" || line == "*** End Patch" { return nil }
            if line.hasPrefix("***") || line.hasPrefix("@@") { return DiffLine(kind: .context, text: line) }
            if line.hasPrefix("-") { return DiffLine(kind: .removed, text: String(line.dropFirst())) }
            if line.hasPrefix("+") { return DiffLine(kind: .added, text: String(line.dropFirst())) }
            if line.hasPrefix(" ") { return DiffLine(kind: .context, text: String(line.dropFirst())) }
            return line.isEmpty ? nil : DiffLine(kind: .context, text: line)
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
        let before = LineDiff.lines(old)
        let after = LineDiff.lines(new)
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

/// Which lines an edit removes and adds.
public enum LineDiff {
    /// Old lines times new lines above which the exact diff costs too much; the shared start
    /// and end are dropped instead and everything between counts as changed.
    public static let cap = 250_000

    /// Empty text is no lines, and a final newline doesn't start one.
    public static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    /// The removed and added lines, in order, from a longest-common-subsequence line diff.
    public static func changes(old: [String], new: [String], cap: Int = cap) -> (removed: [String], added: [String]) {
        var head = 0
        while head < old.count, head < new.count, old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < old.count - head, tail < new.count - head, old[old.count - 1 - tail] == new[new.count - 1 - tail] {
            tail += 1
        }
        let before = Array(old[head..<(old.count - tail)])
        let after = Array(new[head..<(new.count - tail)])
        guard !before.isEmpty, !after.isEmpty, before.count * after.count <= cap else { return (before, after) }
        // lengths[i][j]: the longest common run of before[i...] and after[j...].
        let width = after.count + 1
        var lengths = [Int](repeating: 0, count: (before.count + 1) * width)
        for i in stride(from: before.count - 1, through: 0, by: -1) {
            for j in stride(from: after.count - 1, through: 0, by: -1) {
                lengths[i * width + j] =
                    before[i] == after[j]
                    ? lengths[(i + 1) * width + j + 1] + 1
                    : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }
        var removed: [String] = []
        var added: [String] = []
        var (i, j) = (0, 0)
        while i < before.count, j < after.count {
            if before[i] == after[j] {
                i += 1
                j += 1
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                removed.append(before[i])
                i += 1
            } else {
                added.append(after[j])
                j += 1
            }
        }
        return (removed + before[i...], added + after[j...])
    }
}
