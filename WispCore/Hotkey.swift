/// A keyboard shortcut: a macOS virtual key code plus modifiers.
/// `hyper` means Caps Lock, remapped to F18 and held as a modifier.
public struct Hotkey: Sendable, Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
        public static let hyper = Modifiers(rawValue: 1 << 4)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Caps Lock + Space.
    public static let hyperSpace = Hotkey(keyCode: KeyCodes.space, modifiers: .hyper)
    /// Opens clipboard history when the shelf uses Caps Lock.
    public static let clipboardHyper = Hotkey(keyCode: KeyCodes.v, modifiers: .hyper)
    /// Clipboard history without Caps Lock. Avoids ⇧⌘V (Paste and Match Style).
    public static let clipboardFallback = Hotkey(keyCode: KeyCodes.v, modifiers: [.option, .shift, .command])

    public var usesHyper: Bool { modifiers.contains(.hyper) }

    /// Serialised form, e.g. "hyper+space" or "cmd+shift+k".
    public var stringValue: String {
        (Self.modifierNames.filter { modifiers.contains($0.modifier) }.map(\.name) + [KeyCodes.name(for: keyCode)])
            .joined(separator: "+")
    }

    /// Display form, e.g. "⇪ Space" or "⌘⇧K".
    public var description: String {
        let symbols = Self.modifierNames.filter { modifiers.contains($0.modifier) }.map(\.symbol).joined()
        let key = KeyCodes.displayName(for: keyCode)
        return usesHyper ? "\(symbols) \(key)" : symbols + key
    }

    /// Parses `stringValue`. Needs at least one modifier and exactly one known key.
    public init?(string: String) {
        var modifiers: Modifiers = []
        var keyCode: UInt16?
        for part in string.lowercased().split(separator: "+").map(String.init) {
            if let match = Self.modifierNames.first(where: { $0.name == part || $0.aliases.contains(part) }) {
                modifiers.insert(match.modifier)
            } else if keyCode == nil, let code = KeyCodes.code(for: part) {
                keyCode = code
            } else {
                return nil
            }
        }
        guard let keyCode, !modifiers.isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    // Display order follows the macOS convention: ⌃⌥⇧⌘, with Hyper first.
    private static let modifierNames: [(modifier: Modifiers, name: String, aliases: [String], symbol: String)] = [
        (.hyper, "hyper", ["caps", "capslock"], "⇪"),
        (.control, "ctrl", ["control"], "⌃"),
        (.option, "option", ["alt", "opt"], "⌥"),
        (.shift, "shift", [], "⇧"),
        (.command, "cmd", ["command"], "⌘"),
    ]
}

/// macOS virtual key codes (Carbon `kVK_*`) for the keys Wisp lets users bind.
/// Letters and digits use ANSI positions.
public enum KeyCodes {
    public static let space: UInt16 = 49
    public static let f18: UInt16 = 79
    public static let escape: UInt16 = 53
    public static let v: UInt16 = 9

    /// 1–9 on the number row, for Hyper+digit shortcuts.
    public static func digit(forKeyCode code: UInt16) -> Int? {
        let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        return digits[code]
    }

    private static let table: [(name: String, code: UInt16, display: String)] = {
        let letters: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
            ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("o", 31), ("u", 32),
            ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        let digits: [(String, UInt16)] = [
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28),
            ("0", 29),
        ]
        let named: [(String, UInt16, String)] = [
            ("space", 49, "Space"), ("return", 36, "↩"), ("tab", 48, "⇥"), ("escape", 53, "⎋"),
            ("left", 123, "←"), ("right", 124, "→"), ("down", 125, "↓"), ("up", 126, "↑"),
        ]
        return letters.map { ($0.0, $0.1, $0.0.uppercased()) } + digits.map { ($0.0, $0.1, $0.0) } + named
    }()

    public static func code(for name: String) -> UInt16? {
        table.first { $0.name == name }?.code
    }

    public static func name(for code: UInt16) -> String {
        table.first { $0.code == code }?.name ?? "key\(code)"
    }

    public static func displayName(for code: UInt16) -> String {
        table.first { $0.code == code }?.display ?? "Key \(code)"
    }
}
