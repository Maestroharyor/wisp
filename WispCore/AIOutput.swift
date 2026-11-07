import Foundation

/// Tidies a model's answer: small local models add reasoning blocks, preambles ("Here is the
/// corrected text:"), code fences and quotes around text that should be pasted as is. Each
/// clean-up is skipped when the user's own `input` starts the same way, so their text survives.
public enum AIOutput {
    /// Opening words of a line that introduces the answer instead of being part of it.
    private static let preambles = ["here", "sure", "certainly", "okay", "ok", "of course", "below", "absolutely"]
    private static let quotes = [("\"", "\""), ("\u{201C}", "\u{201D}")]

    /// The engine's reply as an answer for `prompt`. A cut-off reply throws `.cutOff` for tasks
    /// that need the whole answer; for the rest it's returned marked as truncated.
    public static func answer(_ reply: AIReply, for task: AITask, prompt: AIPrompt) throws(AIError) -> AIAnswer {
        if reply.cutOff, task.needsWholeAnswer { throw .cutOff }
        return AIAnswer(
            text: clean(reply.text, for: task, input: prompt.prompt), truncated: prompt.truncated || reply.cutOff)
    }

    /// `raw` tidied. `input` is the text the task was given.
    public static func clean(_ raw: String, for task: AITask, input: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.range(of: "<think>", options: .caseInsensitive) == nil { text = removingThinking(text) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .quickInput = task { return jsonObject(in: text) ?? text }
        if !isPreamble(firstLine(of: input)) { text = removingPreamble(text) }
        if task.isPlainText {
            if !input.hasPrefix("```") { text = unfenced(text) }
            text = unquoted(text, keeping: quotes.filter { input.hasPrefix($0.0) }.map(\.0))
        }
        if case .actionItems = task { text = bulleted(text) }
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops `<think>...</think>` blocks, which reasoning models served by Ollama may put in the
    /// answer. An unclosed block means the answer never started.
    private static func removingThinking(_ text: String) -> String {
        var text = text
        while let open = text.range(of: "<think>", options: .caseInsensitive) {
            guard
                let close = text.range(
                    of: "</think>", options: .caseInsensitive, range: open.upperBound..<text.endIndex)
            else { return String(text[..<open.lowerBound]) }
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text
    }

    private static func firstLine(of text: String) -> String {
        String(text.prefix { $0 != "\n" })
    }

    /// A line like "Here is the corrected text:" or "Sure! Here's a summary:".
    private static func isPreamble(_ line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces).lowercased()
        return line.hasSuffix(":") && preambles.contains { line.hasPrefix($0) }
    }

    private static func removingPreamble(_ text: String) -> String {
        guard let newline = text.firstIndex(of: "\n"), isPreamble(String(text[..<newline])) else { return text }
        return text[newline...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text inside a code fence that wraps the whole answer.
    private static func unfenced(_ text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6,
            let firstBreak = text.firstIndex(of: "\n")
        else { return text }
        let inner = text[text.index(after: firstBreak)..<text.index(text.endIndex, offsetBy: -3)]
        guard !inner.contains("```") else { return text }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text inside one pair of quotes that wraps the whole answer, unless the user's text
    /// opened with that quote too (`keeping`).
    private static func unquoted(_ text: String, keeping: [String]) -> String {
        for (open, close) in quotes where !keeping.contains(open) {
            guard text.count > 2, text.hasPrefix(open), text.hasSuffix(close) else { continue }
            let inner = text.dropFirst().dropLast()
            if !inner.contains(open), !inner.contains(close) {
                return inner.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    /// Every list line as `- item`, whatever bullet or number the model used, with blank lines gone.
    private static func bulleted(_ text: String) -> String {
        text.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            for bullet in ["- ", "* ", "• ", "\u{2013} "] where trimmed.hasPrefix(bullet) {
                return "- " + trimmed.dropFirst(bullet.count).trimmingCharacters(in: .whitespaces)
            }
            let digits = trimmed.prefix(while: \.isNumber)
            let rest = trimmed.dropFirst(digits.count)
            if !digits.isEmpty, let mark = rest.first, mark == "." || mark == ")" {
                return "- " + rest.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            return trimmed
        }
        .joined(separator: "\n")
    }

    /// The outermost `{...}` in `text`.
    private static func jsonObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }
}
