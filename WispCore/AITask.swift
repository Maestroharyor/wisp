import Foundation

/// How a rewrite should sound.
public enum AITone: String, CaseIterable, Sendable {
    case friendly
    case professional
    case shorter
}

/// What Wisp asks the on-device model to do. Each task carries its instructions and how much
/// room its answer needs; the text it works on is the prompt, never part of the instructions.
public enum AITask: Hashable, Sendable {
    case summarise
    case translate(language: String)
    case fixGrammar
    case rewrite(tone: AITone)
    case actionItems
    /// Explains a piece of code or an error message.
    case explain
    /// Summarises a coding-agent session from its structured record (not a transcript).
    case sessionSummary
    /// Turns a short request ("25 min", "remind me at 4 to call Sam") into one JSON object.
    case quickInput(now: Date, timeZone: TimeZone)

    /// The text tasks offered on selected or copied text, in menu order.
    public static let menu: [AITask] = [
        .summarise, .fixGrammar, .rewrite(tone: .friendly), .rewrite(tone: .professional), .rewrite(tone: .shorter),
        .actionItems, .explain,
    ]

    public var title: String {
        switch self {
        case .summarise: "Summarise"
        case .translate(let language): "Translate to \(Self.language(language))"
        case .fixGrammar: "Fix grammar"
        case .rewrite(.friendly): "Make friendlier"
        case .rewrite(.professional): "Make more professional"
        case .rewrite(.shorter): "Make shorter"
        case .actionItems: "Action items"
        case .explain: "Explain"
        case .sessionSummary: "Session summary"
        case .quickInput: "Quick input"
        }
    }

    /// Shared by every task: small models drift into chatter without it.
    private static let plain =
        "Reply with the result only, with no introduction, no closing remarks and no quotation marks around it."

    public var instructions: String {
        switch self {
        case .summarise:
            "Summarise the text the user gives you in two to four short sentences. Keep names, numbers and decisions. "
                + Self.plain
        case .translate(let language):
            "Translate the text the user gives you into \(Self.language(language)). Keep the meaning, tone and "
                + "formatting. " + Self.plain
        case .fixGrammar:
            "Correct the spelling, grammar and punctuation of the text the user gives you. Change as little as "
                + "possible and keep the author's wording, tone and formatting. " + Self.plain
        case .rewrite(let tone):
            "Rewrite the text the user gives you \(Self.toneInstruction(tone)) Keep the meaning and any names, "
                + "numbers and links. " + Self.plain
        case .actionItems:
            "List the action items in the text the user gives you, one per line, each starting with \"- \" and "
                + "beginning with a verb. Include who and when if the text says. If there are none, reply "
                + "\"No action items\". " + Self.plain
        case .explain:
            "Explain the code or error message the user gives you to a developer, in plain words. Say what it "
                + "means, the likely cause and how to fix it. Be brief; use a short code block only if it helps."
        case .sessionSummary:
            "The user gives you a structured record of a coding-agent session. Summarise what was done in one or "
                + "two short sentences, then any open questions or failures. Use only facts in the record. "
                + Self.plain
        case .quickInput(let now, let timeZone):
            "Turn the user's request into one JSON object and nothing else. Fields: \"kind\" (\"timer\", "
                + "\"reminder\" or \"event\"), \"title\" (short text), \"minutes\" (number, for timers and event "
                + "length) and \"date\" (ISO 8601 with offset, for reminders and events). Leave out fields that "
                + "don't apply. It is now \(Self.timestamp(now, timeZone)) in \(timeZone.identifier)."
        }
    }

    /// Room kept for the answer, in tokens. Nil for tasks whose answer is about as long as the
    /// input (translate, fix, rewrite): `AIBudget` gives those as much room as the input.
    public var answerTokens: Int? {
        switch self {
        case .summarise, .sessionSummary: 300
        case .actionItems: 400
        case .explain: 600
        case .quickInput: 150
        case .translate, .fixGrammar, .rewrite: nil
        }
    }

    public var temperature: Double {
        switch self {
        case .quickInput: 0
        case .fixGrammar, .translate: 0.1
        case .actionItems, .sessionSummary, .explain: 0.2
        case .summarise: 0.3
        case .rewrite: 0.5
        }
    }

    /// A cut-off answer is no use: it would replace the user's text with part of it, or it's
    /// half a JSON object. Other tasks can show a partial answer, marked as truncated.
    var needsWholeAnswer: Bool {
        switch self {
        case .translate, .fixGrammar, .rewrite, .quickInput: true
        case .summarise, .sessionSummary, .actionItems, .explain: false
        }
    }

    /// The answer is plain text that replaces or sits beside the input, so fences and quotes go.
    var isPlainText: Bool {
        switch self {
        case .translate, .fixGrammar, .rewrite, .summarise, .sessionSummary: true
        case .actionItems, .explain, .quickInput: false
        }
    }

    private static func language(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "English" : trimmed
    }

    private static func toneInstruction(_ tone: AITone) -> String {
        switch tone {
        case .friendly: "so it sounds warm and friendly but not gushing."
        case .professional: "so it sounds clear, polite and professional."
        case .shorter: "so it is about half as long, dropping filler and repetition."
        }
    }

    private static func timestamp(_ date: Date, _ timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// One request ready for an engine: instructions, the (trimmed) input and the answer's limits.
public struct AIPrompt: Equatable, Sendable {
    public var instructions: String
    public var prompt: String
    public var maximumResponseTokens: Int
    public var temperature: Double
    /// The input was cut to fit the model's window.
    public var truncated: Bool

    public init(instructions: String, prompt: String, maximumResponseTokens: Int, temperature: Double, truncated: Bool)
    {
        self.instructions = instructions
        self.prompt = prompt
        self.maximumResponseTokens = maximumResponseTokens
        self.temperature = temperature
        self.truncated = truncated
    }

    /// An answer that used every token it was allowed most likely stopped mid-sentence. Apple's
    /// model returns such an answer without an error, so the caller has to check.
    public func isCutOff(outputTokens: Int) -> Bool {
        outputTokens >= maximumResponseTokens
    }
}

/// A model's own token count for a prompt, split so a retry knows how much the input can have.
public struct AITokenCount: Equatable, Sendable {
    public let instructions: Int
    public let input: Int

    public init(instructions: Int, input: Int) {
        self.instructions = instructions
        self.input = input
    }
}
