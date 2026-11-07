import Foundation

/// ntfy topics and server addresses. Anyone who knows a topic on a public server can read and
/// post to it, so topics are 128 random bits: unguessable, and the only secret a public topic has.
public enum PushTopic {
    /// Random bytes in a topic or nonce.
    public static let bytes = 16
    /// ntfy allows topic names up to 64 characters of letters, digits, `-` and `_`.
    static let maximumLength = 64

    /// 128 random bits as URL-safe base64 without padding (22 characters).
    public static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// `SystemRandomNumberGenerator` is cryptographically secure on Apple platforms; tests pass
    /// a seeded one.
    public static func random(using generator: inout some RandomNumberGenerator) -> String {
        let data = Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func isValid(_ topic: String) -> Bool {
        !topic.isEmpty && topic.count <= maximumLength
            && topic.unicodeScalars.allSatisfy {
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
            }
    }

    public static let defaultServer = "https://ntfy.sh"

    /// The server as typed, cleaned up: https with a host, no query, no trailing slash. Nil for
    /// anything else; plain http would send the token and the replies in the clear.
    public static func server(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let components = URLComponents(string: trimmed), components.scheme?.lowercased() == "https",
            let host = components.host, !host.isEmpty,
            components.query == nil, components.fragment == nil, components.user == nil
        else { return nil }
        return components.url
    }

    /// `<server>/<topic>`: where to subscribe, and where a reply action posts.
    public static func url(server: URL, topic: String) -> URL? {
        guard isValid(topic) else { return nil }
        return server.appendingPathComponent(topic)
    }

    /// `<server>/<topic>/json`: the topic's message stream, one JSON object per line.
    public static func streamURL(server: URL, topic: String) -> URL? {
        url(server: server, topic: topic)?.appendingPathComponent("json")
    }
}
