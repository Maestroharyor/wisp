import Foundation

/// One line of an edit's diff.
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case context
        case removed
        case added
        /// A header between hunks: one edit of several ("Edit 2 of 3"), lines left out ("⋯"),
        /// or a patch's file and "@@" lines.
        case hunk
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
            return capped(edit(input), limit: limit)
        case "MultiEdit":
            guard case .array(let list) = input?["edits"] else { return nil }
            // Each edit is its own hunk under a header, so a later one isn't read as context.
            let hunks = list.enumerated().map { index, item in
                let lines = edit(item)
                guard list.count > 1, !lines.isEmpty else { return lines }
                return [DiffLine(kind: .hunk, text: "Edit \(index + 1) of \(list.count)")] + lines
            }
            return capped(hunks.flatMap { $0 }, limit: limit)
        case "apply_patch":
            guard let patch = input?["command"]?.stringValue else { return nil }
            return capped(patchLines(patch), limit: limit)
        case "Write":
            return capped(input?["content"]?.stringValue, limit: limit)
        // OpenCode names its shell permission "bash".
        case "Bash", "bash":
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

    /// One edit as a unified diff: its changes in place, with `contextLines` around each.
    private static func edit(_ edit: JSONValue?) -> [DiffLine] {
        guard let old = edit?["old_string"]?.stringValue, let new = edit?["new_string"]?.stringValue else {
            return []
        }
        return LineDiff.unified(old: LineDiff.lines(old), new: LineDiff.lines(new), context: contextLines)
    }

    /// Codex's patch format, shown as it is: "-" and "+" lines, with file headers and "@@" as
    /// hunk headers.
    static func patchLines(_ patch: String) -> [DiffLine] {
        patch.components(separatedBy: "\n").compactMap { raw in
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line == "*** Begin Patch" || line == "*** End Patch" { return nil }
            if line.hasPrefix("***") || line.hasPrefix("@@") { return DiffLine(kind: .hunk, text: line) }
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
}

/// Which lines an edit removes and adds.
public enum LineDiff {
    /// Old lines times new lines above which the exact diff costs too much; the shared start
    /// and end are dropped instead and everything between counts as changed.
    public static let cap = 250_000

    /// What stands for lines a unified diff leaves out between two hunks.
    public static let gap = "⋯"

    /// Empty text is no lines, and a final newline doesn't start one.
    public static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    /// The removed and added lines, in order, from a longest-common-subsequence line diff.
    public static func changes(old: [String], new: [String], cap: Int = cap) -> (removed: [String], added: [String]) {
        let lines = operations(old: old, new: new, cap: cap)
        return (lines.filter { $0.kind == .removed }.map(\.text), lines.filter { $0.kind == .added }.map(\.text))
    }

    /// The changes in place with up to `context` unchanged lines around each; runs of unchanged
    /// lines further from a change become one `LineDiff.gap` header. Nothing when nothing changes.
    public static func unified(old: [String], new: [String], context: Int, cap: Int = cap) -> [DiffLine] {
        let lines = operations(old: old, new: new, cap: cap)
        let changed = lines.indices.filter { lines[$0].kind != .context }
        guard !changed.isEmpty else { return [] }
        // Each line's distance to the nearest change, from both directions.
        var distance = [Int](repeating: .max, count: lines.count)
        var last: Int?
        for index in lines.indices {
            if lines[index].kind != .context { last = index }
            if let last { distance[index] = index - last }
        }
        last = nil
        for index in lines.indices.reversed() {
            if lines[index].kind != .context { last = index }
            if let last { distance[index] = min(distance[index], last - index) }
        }
        var result: [DiffLine] = []
        var skipped = false
        for index in lines.indices {
            guard distance[index] <= context else {
                skipped = true
                continue
            }
            // Lines left out between two kept ones; leading and trailing ones just go.
            if skipped, !result.isEmpty { result.append(DiffLine(kind: .hunk, text: gap)) }
            skipped = false
            result.append(lines[index])
        }
        return result
    }

    /// Every line of both sides in order: shared lines as context, then what's removed and
    /// added, from a longest-common-subsequence diff. Above `cap` the shared start and end are
    /// kept and the whole middle counts as removed and added.
    static func operations(old: [String], new: [String], cap: Int) -> [DiffLine] {
        var head = 0
        while head < old.count, head < new.count, old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < old.count - head, tail < new.count - head, old[old.count - 1 - tail] == new[new.count - 1 - tail] {
            tail += 1
        }
        let leading = old[..<head].map { DiffLine(kind: .context, text: $0) }
        let trailing = old[(old.count - tail)...].map { DiffLine(kind: .context, text: $0) }
        let before = Array(old[head..<(old.count - tail)])
        let after = Array(new[head..<(new.count - tail)])
        guard !before.isEmpty, !after.isEmpty, before.count * after.count <= cap else {
            return leading + before.map { DiffLine(kind: .removed, text: $0) }
                + after.map { DiffLine(kind: .added, text: $0) } + trailing
        }
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
        var middle: [DiffLine] = []
        var (i, j) = (0, 0)
        while i < before.count, j < after.count {
            if before[i] == after[j] {
                middle.append(DiffLine(kind: .context, text: before[i]))
                i += 1
                j += 1
            } else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] {
                middle.append(DiffLine(kind: .removed, text: before[i]))
                i += 1
            } else {
                middle.append(DiffLine(kind: .added, text: after[j]))
                j += 1
            }
        }
        middle += before[i...].map { DiffLine(kind: .removed, text: $0) }
        middle += after[j...].map { DiffLine(kind: .added, text: $0) }
        return leading + middle + trailing
    }
}
