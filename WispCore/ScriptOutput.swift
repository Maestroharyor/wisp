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

    /// The window page shows whole lines; past this they're cut so one huge line can't stall layout.
    public static let maxTranscriptLineLength = 1000

    /// Output as a terminal shows it, for the window page: colours removed, blank lines and
    /// indentation inside kept, blank lines at either end and trailing spaces dropped.
    public static func transcript(from output: String, limit: Int) -> [String] {
        var lines = stripColours(output)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line.prefix(maxTranscriptLineLength)).replacingOccurrences(
                    of: "\\s+$", with: "", options: .regularExpression)
            }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return Array(lines.prefix(max(limit, 0)))
    }

    /// Seconds between runs: at least 10, so a script can't keep the Mac busy, at most an hour.
    public static func clampedInterval(_ seconds: Double) -> Double {
        min(max(seconds, 10), 3600)
    }

    private enum EscapeState { case text, escape, control, command, commandEscape }

    /// Removes ANSI escape sequences: colour codes (`ESC [ ... m`) and commands such as
    /// hyperlinks and window titles (`ESC ] ... BEL` or `ESC ] ... ESC \`).
    private static func stripColours(_ text: String) -> String {
        var result = ""
        var state = EscapeState.text
        for scalar in text.unicodeScalars {
            switch state {
            case .text:
                if scalar == "\u{1B}" { state = .escape } else { result.unicodeScalars.append(scalar) }
            case .escape:
                if scalar == "[" {
                    state = .control
                } else if scalar == "]" {
                    state = .command
                } else if !(0x20...0x2F).contains(scalar.value) {
                    state = .text
                }
            case .control:
                if (0x40...0x7E).contains(scalar.value) { state = .text }
            case .command:
                if scalar == "\u{07}" { state = .text } else if scalar == "\u{1B}" { state = .commandEscape }
            case .commandEscape:
                state = scalar == "\\" ? .text : .command
            }
        }
        return result
    }
}
