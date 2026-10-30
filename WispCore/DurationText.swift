import Foundation

/// Typed durations such as "2h15m", "90s" or "25" (plain numbers are minutes).
public enum DurationText {
    public static func seconds(from text: String) -> TimeInterval? {
        let compact = text.lowercased().filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }
        if let minutes = Int(compact) { return minutes > 0 ? TimeInterval(minutes * 60) : nil }

        var total = 0
        var digits = ""
        for character in compact {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let value = Int(digits) else { return nil }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: return nil
            }
            digits = ""
        }
        guard digits.isEmpty, total > 0 else { return nil }
        return TimeInterval(total)
    }

    public static func text(for seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let parts = [(total / 3600, "h"), (total % 3600 / 60, "m"), (total % 60, "s")]
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
}
