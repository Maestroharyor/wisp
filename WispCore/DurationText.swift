import Foundation

/// Typed durations such as "2h15m", "90s" or "25" (plain numbers are minutes).
public enum DurationText {
    public static func seconds(from text: String) -> TimeInterval? {
        let compact = text.lowercased().filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }
        if let minutes = Int(compact) {
            guard minutes > 0, let seconds = adding(0, minutes, times: 60) else { return nil }
            return TimeInterval(seconds)
        }

        var total = 0
        var digits = ""
        for character in compact {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let value = Int(digits) else { return nil }
            let unit: Int
            switch character {
            case "h": unit = 3600
            case "m": unit = 60
            case "s": unit = 1
            default: return nil
            }
            // Very long numbers would trap on overflow; treat them as invalid input.
            guard let sum = adding(total, value, times: unit) else { return nil }
            total = sum
            digits = ""
        }
        guard digits.isEmpty, total > 0 else { return nil }
        return TimeInterval(total)
    }

    /// `total + value * unit`, or nil when it overflows.
    private static func adding(_ total: Int, _ value: Int, times unit: Int) -> Int? {
        let product = value.multipliedReportingOverflow(by: unit)
        guard !product.overflow else { return nil }
        let sum = total.addingReportingOverflow(product.partialValue)
        return sum.overflow ? nil : sum.partialValue
    }

    public static func text(for seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let parts = [(total / 3600, "h"), (total % 3600 / 60, "m"), (total % 60, "s")]
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
}
