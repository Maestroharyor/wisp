import Foundation

/// Hex text for the colour picker, from sRGB components in 0...1.
public enum ColorHex {
    public static func string(red: Double, green: Double, blue: Double) -> String {
        let bytes = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return "#" + bytes.map { String(format: "%02X", $0) }.joined()
    }
}
