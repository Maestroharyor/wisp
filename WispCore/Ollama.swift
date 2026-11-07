import Foundation

/// Where Wisp talks to Ollama. Only a server on this Mac is accepted, so text never leaves it.
public enum OllamaEndpoint {
    /// Ollama's default address. 127.0.0.1 rather than localhost, which may resolve to ::1 first.
    public static let defaultAddress = "http://127.0.0.1:11434"
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// The address as typed, cleaned up: http or https on localhost, 127.0.0.1 or ::1, with no
    /// user, path, query or fragment. Nil for anything else.
    public static func base(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.isEmpty, !trimmed.contains("://") { trimmed = "http://" + trimmed }
        guard var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            components.user == nil, components.password == nil, components.path.isEmpty,
            components.query == nil, components.fragment == nil,
            let host = components.host?.lowercased(), localHosts.contains(host)
        else { return nil }
        components.scheme = scheme
        components.host = host
        return components.url
    }

    /// True only for http(s) URLs whose host is this Mac. Checked again before every request.
    public static func isLocal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else { return false }
        return localHosts.contains(host)
    }

    public static func chatURL(_ base: URL) -> URL {
        base.appendingPathComponent("api").appendingPathComponent("chat")
    }

    public static func tagsURL(_ base: URL) -> URL {
        base.appendingPathComponent("api").appendingPathComponent("tags")
    }
}

/// What went wrong talking to Ollama.
public enum OllamaError: Error, Equatable, Sendable {
    /// Ollama answered with `{"error": "..."}`.
    case server(String)
    case unreadable
}

/// `POST /api/chat` without streaming: a system message with the instructions, a user message
/// with the input, and the answer in `message.content`.
public enum OllamaChat {
    struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Options: Encodable {
            let temperature: Double
            let maximumTokens: Int
            let contextTokens: Int

            enum CodingKeys: String, CodingKey {
                case temperature
                case maximumTokens = "num_predict"
                case contextTokens = "num_ctx"
            }
        }

        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options
    }

    struct Response: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
        let error: String?
        let doneReason: String?

        enum CodingKeys: String, CodingKey {
            case message, error
            case doneReason = "done_reason"
        }
    }

    public static func body(model: String, prompt: AIPrompt) throws -> Data {
        let request = Request(
            model: model,
            messages: [
                .init(role: "system", content: prompt.instructions), .init(role: "user", content: prompt.prompt),
            ],
            stream: false,
            options: .init(
                temperature: prompt.temperature, maximumTokens: prompt.maximumResponseTokens,
                contextTokens: AIBudget.contextTokens))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(request)
    }

    /// The answer, cut off when it stopped at `num_predict` (`done_reason` "length"), or Ollama's
    /// error message. Reasoning models may also send `message.thinking`, which is ignored.
    public static func content(from data: Data) -> Result<AIReply, OllamaError> {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return .failure(.unreadable) }
        if let error = response.error { return .failure(.server(error)) }
        guard let content = response.message?.content else { return .failure(.unreadable) }
        return .success(AIReply(text: content, cutOff: response.doneReason == "length"))
    }
}

/// A model Ollama has pulled.
public struct OllamaModel: Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    /// Parameter size, such as "3.2B".
    public let detail: String?
    public var id: String { name }

    public init(name: String, detail: String?) {
        self.name = name
        self.detail = detail
    }
}

/// `GET /api/tags`: the models Ollama has pulled.
public enum OllamaTags {
    struct Response: Decodable {
        struct Model: Decodable {
            struct Details: Decodable {
                let family: String?
                let families: [String]?
                let parameterSize: String?

                enum CodingKeys: String, CodingKey {
                    case family, families
                    case parameterSize = "parameter_size"
                }
            }

            let name: String
            let details: Details?
        }

        let models: [Model]
    }

    /// Families of embedding models, which can't chat.
    private static let embeddingFamilies: Set<String> = ["nomic-bert", "bert"]

    /// Chat-capable models, sorted by name.
    public static func models(from data: Data) throws -> [OllamaModel] {
        try JSONDecoder().decode(Response.self, from: data).models
            .filter { model in
                let families = Set((model.details?.families ?? []) + [model.details?.family].compactMap { $0 })
                return families.isDisjoint(with: embeddingFamilies) && !model.name.contains("embed")
            }
            .map { OllamaModel(name: $0.name, detail: $0.details?.parameterSize) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether `name` is among `models`. A name without a tag means `:latest`, as in `ollama run`.
    public static func has(_ name: String, in models: [OllamaModel]) -> Bool {
        let wanted = name.contains(":") ? name : name + ":latest"
        return models.contains { $0.name == name || $0.name == wanted }
    }

    /// The model to use: the saved one (even if it's gone, so the status can say so), or else
    /// the first one pulled.
    public static func choose(saved: String, from models: [OllamaModel]) -> String? {
        saved.isEmpty ? models.first?.name : saved
    }
}
