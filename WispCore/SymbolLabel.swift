import Foundation

/// Spoken names for icon-only buttons, so VoiceOver says "Next" rather than "forward.fill".
public enum SymbolLabel {
    private static let known: [String: String] = [
        "play.fill": "Play",
        "pause.fill": "Pause",
        "forward.fill": "Next",
        "backward.fill": "Previous",
        "xmark": "Close",
        "arrow.counterclockwise": "Reset",
        "pip": "Mini player",
    ]

    public static func label(for symbol: String) -> String {
        if let name = known[symbol] { return name }
        let words = symbol.split(separator: ".").filter { $0 != "fill" && $0 != "circle" }.joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
