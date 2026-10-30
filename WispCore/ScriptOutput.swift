import Foundation

/// Tidies a user script's output for the Script widget.
public enum ScriptOutput {
    public static let maxLineLength = 120

    public static func lines(from output: String, limit: Int) -> [String] {
        Array(
            stripColours(output)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .prefix(max(limit, 0))
                .map { String($0.prefix(maxLineLength)) })
    }

    /// Seconds between runs: at least 10, so a script can't keep the Mac busy, at most an hour.
    public static func clampedInterval(_ seconds: Double) -> Double {
        min(max(seconds, 10), 3600)
    }

    /// Removes ANSI escape sequences such as colour codes.
    private static func stripColours(_ text: String) -> String {
        var result = ""
        var inEscape = false
        var sawBracket = false
        for scalar in text.unicodeScalars {
            if inEscape {
                if !sawBracket, scalar == "[" {
                    sawBracket = true
                } else if (0x40...0x7E).contains(scalar.value) {
                    inEscape = false
                }
                continue
            }
            if scalar == "\u{1B}" {
                inEscape = true
                sawBracket = false
                continue
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
