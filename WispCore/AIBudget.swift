import Foundation

/// Fits a task's input into the model's context window, leaving room for the instructions and
/// the answer. Apple's on-device model has a 4,096-token window; Ollama is asked for the same.
/// Tokens are estimated from characters, on the high side; the app checks the estimate with
/// the framework's own count where there is one and trims again with `refit`.
public enum AIBudget {
    public static let contextTokens = 4_096
    /// Chat template and role markers the engine adds around the text.
    public static let overheadTokens = 64
    /// Stands in for the part of the input that was cut.
    public static let gapMarker = "[...]"
    private static let gap = "\n\(gapMarker)\n"
    /// Where a cut may fall, best first.
    private static let separators: [Unicode.Scalar] = ["\n", " "]

    /// About three ASCII letters or spaces to a token, and a token for every digit, punctuation
    /// mark and non-ASCII character. Checked against Apple's model on macOS 27, where digits and
    /// punctuation split densely: prose comes out well above its real count, logs full of
    /// numbers only just above it.
    public static func estimateTokens(_ text: String) -> Int {
        var count = TokenCount()
        for scalar in text.unicodeScalars { count.add(scalar) }
        return count.tokens
    }

    /// Running totals for the estimate, so trimming can count as it goes.
    private struct TokenCount {
        var light = 0
        var heavy = 0

        mutating func add(_ scalar: Unicode.Scalar) {
            if scalar.isASCII, scalar.properties.isAlphabetic || scalar.properties.isWhitespace {
                light += 1
            } else {
                heavy += 1
            }
        }

        var tokens: Int { (light + 2) / 3 + heavy }
    }

    /// The window less the task's instructions and the overhead: what the input and answer share.
    private static func freeTokens(for task: AITask, contextTokens: Int) -> Int {
        max(0, contextTokens - estimateTokens(task.instructions) - overheadTokens)
    }

    /// The most input the task takes. Tasks whose answer is as long as their input (translate,
    /// fix, rewrite) get half the free room, so the answer always has at least as much.
    public static func inputTokens(for task: AITask, contextTokens: Int = contextTokens) -> Int {
        let free = freeTokens(for: task, contextTokens: contextTokens)
        guard let answer = task.answerTokens else { return free / 2 }
        return max(0, free - answer)
    }

    /// The least room the task's answer gets.
    public static func answerTokens(for task: AITask, contextTokens: Int = contextTokens) -> Int {
        let free = freeTokens(for: task, contextTokens: contextTokens)
        return task.answerTokens ?? free - free / 2
    }

    /// The task's request with `input` trimmed to fit. Same-length tasks give the answer all the
    /// room the input didn't use. `inputLimit` overrides the room for the input, for `refit`.
    public static func prompt(
        for task: AITask, input: String, contextTokens: Int = contextTokens, inputLimit: Int? = nil
    ) -> AIPrompt {
        let limit = inputLimit ?? inputTokens(for: task, contextTokens: contextTokens)
        let trimmed = trim(input.trimmingCharacters(in: .whitespacesAndNewlines), toTokens: limit)
        let answer =
            task.answerTokens
            ?? max(
                answerTokens(for: task, contextTokens: contextTokens),
                freeTokens(for: task, contextTokens: contextTokens) - estimateTokens(trimmed.text))
        return AIPrompt(
            instructions: task.instructions, prompt: trimmed.text, maximumResponseTokens: answer,
            temperature: task.temperature, truncated: trimmed.truncated)
    }

    /// `prompt` made to fit the model's own `count`: `prompt` itself if it fits, nil if nothing
    /// can. Same-length tasks first give up answer room the input doesn't need, down to
    /// `answerTokens(for:)`. Only then is the input trimmed, scaled from what the model counted
    /// for it with 5% to spare, and the answer keeps its floor.
    public static func refit(
        _ prompt: AIPrompt, task: AITask, input: String, contextTokens: Int, count: AITokenCount
    ) -> AIPrompt? {
        let room = contextTokens - count.instructions - count.input - overheadTokens
        guard room < prompt.maximumResponseTokens else { return prompt }
        let floor = min(answerTokens(for: task, contextTokens: contextTokens), prompt.maximumResponseTokens)
        if room >= floor {
            var lowered = prompt
            lowered.maximumResponseTokens = room
            return lowered
        }
        let allowed = contextTokens - floor - overheadTokens
        let limit = shrink(
            limit: estimateTokens(prompt.prompt), measured: count.input, allowed: allowed - count.instructions)
        var next = self.prompt(for: task, input: input, contextTokens: contextTokens, inputLimit: limit)
        guard !next.prompt.isEmpty, next.prompt.unicodeScalars.count < prompt.prompt.unicodeScalars.count else {
            return nil
        }
        next.maximumResponseTokens = floor
        next.truncated = true
        return next
    }

    /// A smaller input limit after the framework measured `measured` tokens where `allowed` fit,
    /// with 5% to spare.
    public static func shrink(limit: Int, measured: Int, allowed: Int) -> Int {
        guard allowed > 0, limit > 0 else { return 0 }
        guard measured > allowed else { return limit }
        return Int(Double(limit) * Double(allowed) / Double(measured) * 0.95)
    }

    /// `text` cut to at most `limit` estimated tokens. Keeps the start (two thirds) and the end
    /// (one third), since the end of a log or error usually matters as much as its start, and
    /// cuts on line breaks where it can.
    public static func trim(_ text: String, toTokens limit: Int) -> (text: String, truncated: Bool) {
        if estimateTokens(text) <= limit { return (text, false) }
        let room = limit - estimateTokens(gap)
        guard room > 0 else { return ("", !text.isEmpty) }
        let scalars = Array(text.unicodeScalars)
        let headRoom = room * 2 / 3
        let headEnd = lineCut(scalars, end: prefixLength(scalars, tokens: headRoom))
        let tailLength = prefixLength(scalars.reversed(), tokens: room - headRoom)
        let tailStart = max(headEnd, lineStart(scalars, start: scalars.count - tailLength))
        let head = string(scalars[..<headEnd])
        let tail = string(scalars[tailStart...])
        return (head + gap + tail, true)
    }

    /// How many scalars from the start of `scalars` fit in `tokens`.
    private static func prefixLength(_ scalars: some Sequence<Unicode.Scalar>, tokens limit: Int) -> Int {
        var count = TokenCount()
        var length = 0
        for scalar in scalars {
            count.add(scalar)
            if count.tokens > limit { break }
            length += 1
        }
        return length
    }

    /// Moves `end` back to the last line break (or space) before it, unless that loses more
    /// than half of what was kept.
    private static func lineCut(_ scalars: [Unicode.Scalar], end: Int) -> Int {
        guard end < scalars.count, end > 0, scalars[end] != "\n" else { return end }
        for separator in separators {
            if let index = scalars[..<end].lastIndex(of: separator), index >= end / 2 {
                return index
            }
        }
        return end
    }

    /// Moves `start` forward past the next line break (or space), unless that loses more than
    /// half of what was kept.
    private static func lineStart(_ scalars: [Unicode.Scalar], start: Int) -> Int {
        guard start > 0, start < scalars.count, scalars[start - 1] != "\n" else { return start }
        let kept = scalars.count - start
        for separator in separators {
            if let index = scalars[start...].firstIndex(of: separator),
                index - start <= kept / 2
            {
                return index + 1
            }
        }
        return start
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
