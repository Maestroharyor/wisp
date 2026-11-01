import Foundation

/// Short, readable model names for model ids found in transcripts and hooks.
public enum ModelName {
    /// "claude-opus-4-1-20250805" gives "Opus 4.1", "claude-3-5-sonnet-latest" gives
    /// "Sonnet 3.5". Ids that aren't Claude's come back as they are.
    public static func display(_ id: String) -> String {
        let base = id.split(separator: "[").first.map(String.init) ?? id
        guard base.hasPrefix("claude-") else { return id }
        var family: String?
        var numbers: [String] = []
        for part in base.dropFirst("claude-".count).split(separator: "-") {
            if part.allSatisfy(\.isNumber) {
                // A date stamp ("20250805") isn't part of the version.
                if part.count < 4 { numbers.append(String(part)) }
            } else if family == nil, part != "latest" {
                family = part.prefix(1).uppercased() + part.dropFirst()
            }
        }
        guard let family else { return id }
        return numbers.isEmpty ? family : "\(family) \(numbers.joined(separator: "."))"
    }
}
