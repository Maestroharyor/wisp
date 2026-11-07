import Foundation

/// Which on-device model answers. Both run on this Mac; neither sends text anywhere else.
public enum AIEngineKind: String, CaseIterable, Sendable {
    /// Apple's Foundation Models framework (Apple Intelligence, macOS 26 or later).
    case apple
    /// An Ollama server on this Mac.
    case ollama

    public static let `default` = AIEngineKind.apple

    public var title: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .ollama: "Ollama"
        }
    }
}

/// Whether the chosen engine can answer now, and the status line Settings shows.
public enum AIAvailability: Equatable, Sendable {
    case ready(model: String?)
    /// AI is turned off in Settings.
    case off
    case checking
    case needsNewerMacOS
    case deviceNotEligible
    case appleIntelligenceOff
    /// Apple's model is still downloading or getting ready.
    case modelNotReady
    case ollamaNotRunning
    case ollamaNoModels
    case ollamaModelMissing(String)
    /// The Ollama address isn't on this Mac, so Wisp won't use it.
    case notLocal

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .ready(let model?): "Ready with \(model)"
        case .ready(nil): "Ready"
        case .off: "Off"
        case .checking: "Checking..."
        case .needsNewerMacOS: "Apple Intelligence needs macOS 26 or later"
        case .deviceNotEligible: "This Mac doesn't support Apple Intelligence"
        case .appleIntelligenceOff: "Apple Intelligence is off"
        case .modelNotReady: "Apple Intelligence is still getting ready"
        case .ollamaNotRunning: "Ollama isn't running"
        case .ollamaNoModels: "Ollama has no models. Pull one with \"ollama pull llama3.2\"."
        case .ollamaModelMissing(let model): "Ollama doesn't have \(model)"
        case .notLocal: "Only an Ollama server on this Mac can be used"
        }
    }
}

/// Why a request didn't produce an answer.
public enum AIError: Error, Equatable, Sendable {
    case unavailable(AIAvailability)
    /// The model declined, for example on a safety guardrail.
    case refused
    case unsupportedLanguage
    case tooLong
    /// The answer hit its token limit and stopped part way, so it isn't safe to use.
    case cutOff
    case failed

    public var message: String {
        switch self {
        case .unavailable(let status): status.message
        case .refused: "The model declined to answer"
        case .unsupportedLanguage: "The model doesn't support this language"
        case .tooLong: "The text is too long for the model"
        case .cutOff: "The answer was too long and got cut off"
        case .failed: "The model couldn't answer"
        }
    }
}

/// What an engine sent back, before clean-up.
public struct AIReply: Equatable, Sendable {
    public let text: String
    /// The answer used every token it was allowed and stopped part way.
    public let cutOff: Bool

    public init(text: String, cutOff: Bool) {
        self.text = text
        self.cutOff = cutOff
    }
}

/// A cleaned-up answer.
public struct AIAnswer: Equatable, Sendable {
    public let text: String
    /// The input was cut to fit, or the answer stopped part way, so it covers only part of the text.
    public let truncated: Bool

    public init(text: String, truncated: Bool) {
        self.text = text
        self.truncated = truncated
    }
}
