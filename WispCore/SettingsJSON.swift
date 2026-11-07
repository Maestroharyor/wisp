import Foundation

/// Reading and writing agent settings files (Claude Code's settings.json, Codex's hooks.json)
/// whose shape Wisp doesn't own.
enum SettingsJSON {
    /// The file's top-level object; an empty or blank file reads as an empty object. Nil when
    /// the JSON is valid but not an object. Throws when it isn't JSON at all.
    static func object(_ data: Data) throws -> [String: JSONValue]? {
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard case .object(let root) = try JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return root
    }

    /// Pretty-printed with sorted keys, so a rewritten file stays readable and diffs stay small.
    static func encode(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
