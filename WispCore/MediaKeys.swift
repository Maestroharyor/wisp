import Foundation

/// The hardware keys Wisp replaces the system overlay for.
public enum MediaKey: Int, Sendable, Equatable {
    // NX_KEYTYPE_* values from IOKit's ev_keymap.h.
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

/// A decoded `NSEvent` of type systemDefined, subtype 8 (auxiliary control button).
public struct MediaKeyEvent: Sendable, Equatable {
    public let key: MediaKey
    public let isDown: Bool
    public let isRepeat: Bool

    /// `data1` packs the key code in bits 16-31, the key state in bits 8-15
    /// (0x0A down, 0x0B up) and the repeat flag in bit 0.
    public init?(data1: Int) {
        guard let key = MediaKey(rawValue: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        self.key = key
        isDown = ((data1 & 0xFF00) >> 8) == 0x0A
        isRepeat = (data1 & 0x1) == 1
    }
}

/// Volume and brightness stepping: 16 steps like the system, 64 with Option+Shift.
public enum LevelStep {
    public static func next(from value: Double, up: Bool, fine: Bool) -> Double {
        next(from: value, up: up, steps: fine ? 64 : 16)
    }

    public static func next(from value: Double, up: Bool, steps count: Int) -> Double {
        let steps = Double(max(count, 1))
        let scaled = value * steps
        // Tolerance so values that are on the grid (give or take float noise) step a whole notch.
        let target = up ? (scaled + 1e-6).rounded(.down) + 1 : (scaled - 1e-6).rounded(.up) - 1
        return min(max(target / steps, 0), 1)
    }

    public static func percent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}
