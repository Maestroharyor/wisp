import Foundation
import OSLog
import WispCore

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// A language model on this Mac. Engines never log prompts or answers.
protocol AIEngine: Sendable {
    func availability() async -> AIAvailability
    /// The model's context window in tokens.
    func contextTokens() async -> Int
    /// The model's own count for the instructions and the input, or nil when there's only the estimate.
    func countTokens(_ prompt: AIPrompt) async -> AITokenCount?
    /// The answer, marked cut off when it ran out of tokens part way and the engine can tell.
    func respond(to prompt: AIPrompt) async throws(AIError) -> AIReply
}

/// Apple's on-device model through the Foundation Models framework (macOS 26 or later, with
/// Apple Intelligence on). Each request gets a fresh session, so nothing carries over between them.
struct FoundationModelsEngine: AIEngine {
    func availability() async -> AIAvailability {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                switch SystemLanguageModel.default.availability {
                case .available: return .ready(model: nil)
                case .unavailable(.deviceNotEligible): return .deviceNotEligible
                case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceOff
                // modelNotReady, and any reason a later macOS adds.
                case .unavailable: return .modelNotReady
                }
            }
        #endif
        return .needsNewerMacOS
    }

    // contextSize and tokenCount(for:) came with the macOS 26.4 SDK (contextSize is back-deployed to
    // 26.0). The compiler check asks for Swift 6.4 (Xcode 27), the newest toolchain confirmed to have
    // them; older toolchains use the documented 4,096 and the estimate alone.

    func contextTokens() async -> Int {
        #if canImport(FoundationModels) && compiler(>=6.4)
            if #available(macOS 26, *) { return SystemLanguageModel.default.contextSize }
        #endif
        return AIBudget.contextTokens
    }

    func countTokens(_ prompt: AIPrompt) async -> AITokenCount? {
        #if canImport(FoundationModels) && compiler(>=6.4)
            if #available(macOS 26.4, *) {
                let model = SystemLanguageModel.default
                do {
                    let instructions = try await model.tokenCount(for: Instructions(prompt.instructions))
                    let input = try await model.tokenCount(for: Prompt(prompt.prompt))
                    return AITokenCount(instructions: instructions, input: input)
                } catch {
                    return nil
                }
            }
        #endif
        return nil
    }

    func respond(to prompt: AIPrompt) async throws(AIError) -> AIReply {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                let session = LanguageModelSession(instructions: prompt.instructions)
                let options = GenerationOptions(
                    temperature: prompt.temperature, maximumResponseTokens: prompt.maximumResponseTokens)
                let response: LanguageModelSession.Response<String>
                do {
                    response = try await session.respond(to: prompt.prompt, options: options)
                } catch {
                    throw Self.describe(error)
                }
                // An answer that reaches maximumResponseTokens comes back cut short with no error.
                // macOS 27 reports the tokens it used; earlier versions can't tell.
                #if compiler(>=6.4)
                    if #available(macOS 27, *) {
                        let cutOff = prompt.isCutOff(outputTokens: response.usage.output.totalTokenCount)
                        return AIReply(text: response.content, cutOff: cutOff)
                    }
                #endif
                return AIReply(text: response.content, cutOff: false)
            }
        #endif
        throw .unavailable(.needsNewerMacOS)
    }

    #if canImport(FoundationModels)
        /// Framework errors as `AIError`. macOS 27 throws `LanguageModelError`; macOS 26 throws
        /// `GenerationError`. Matching an error's type is the only way to tell them apart.
        @available(macOS 26, *)
        private static func describe(_ error: any Error) -> AIError {
            #if compiler(>=6.4)
                if #available(macOS 27, *), let failure = error as? LanguageModelError {
                    switch failure {
                    case .contextSizeExceeded: return .tooLong
                    case .guardrailViolation, .refusal: return .refused
                    case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                    default: return .failed
                    }
                }
            #endif
            guard let failure = error as? LanguageModelSession.GenerationError else { return .failed }
            switch failure {
            case .exceededContextWindowSize: return .tooLong
            case .guardrailViolation, .refusal: return .refused
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .assetsUnavailable: return .unavailable(.modelNotReady)
            default: return .failed
            }
        }
    #endif
}

/// An Ollama server on this Mac. Every request checks the address is local, goes through a
/// session with no proxy, and refuses redirects, so text can't be sent anywhere else.
struct OllamaEngine: AIEngine {
    /// Nil when the address isn't on this Mac.
    let base: URL?
    let model: String?

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()
    private static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "ai")

    init(address: String, model: String) {
        base = OllamaEndpoint.base(address)
        self.model = model.isEmpty ? nil : model
    }

    func availability() async -> AIAvailability {
        do {
            return status(models: try await models())
        } catch {
            if case .unavailable(let status) = error { return status }
            return .ollamaNotRunning
        }
    }

    /// Ready when the chosen model, or else any model, has been pulled.
    func status(models: [OllamaModel]) -> AIAvailability {
        guard let chosen = OllamaTags.choose(saved: model ?? "", from: models) else { return .ollamaNoModels }
        return OllamaTags.has(chosen, in: models) ? .ready(model: chosen) : .ollamaModelMissing(chosen)
    }

    /// The chat-capable models Ollama has pulled.
    func models() async throws(AIError) -> [OllamaModel] {
        guard let base else { throw .unavailable(.notLocal) }
        let request = URLRequest(url: OllamaEndpoint.tagsURL(base), timeoutInterval: 3)
        let (data, status) = try await send(request, onTimeout: .unavailable(.ollamaNotRunning))
        guard (200..<300).contains(status), let models = try? OllamaTags.models(from: data) else {
            throw .unavailable(.ollamaNotRunning)
        }
        return models
    }

    func contextTokens() async -> Int { AIBudget.contextTokens }

    func countTokens(_ prompt: AIPrompt) async -> AITokenCount? { nil }

    func respond(to prompt: AIPrompt) async throws(AIError) -> AIReply {
        guard let base else { throw .unavailable(.notLocal) }
        guard let name = try await chosenModel() else { throw .unavailable(.ollamaNoModels) }
        // A cold model can take a while to load before it answers.
        var request = URLRequest(url: OllamaEndpoint.chatURL(base), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? OllamaChat.body(model: name, prompt: prompt) else { throw .failed }
        request.httpBody = body
        let (data, status) = try await send(request, onTimeout: .failed)
        switch OllamaChat.content(from: data) {
        case .success(let reply) where (200..<300).contains(status):
            return reply
        case .failure(.server) where status == 404:
            throw .unavailable(.ollamaModelMissing(name))
        default:
            Self.log.error("ollama chat failed: status \(status, privacy: .public)")
            throw .failed
        }
    }

    private func chosenModel() async throws(AIError) -> String? {
        if let model { return model }
        return try await models().first?.name
    }

    /// Sends `request` if it's for this Mac. A timeout throws `onTimeout` (for the model list,
    /// Ollama isn't answering; for a chat, the model took too long); any other failure to connect
    /// means Ollama isn't running.
    private func send(_ request: URLRequest, onTimeout: AIError) async throws(AIError) -> (Data, Int) {
        guard let url = request.url, OllamaEndpoint.isLocal(url) else { throw .unavailable(.notLocal) }
        do {
            let (data, response) = try await Self.session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError where error.code == .timedOut {
            throw onTimeout
        } catch {
            throw .unavailable(.ollamaNotRunning)
        }
    }
}

/// Refuses every redirect, so a local server can't forward a request off the Mac.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
