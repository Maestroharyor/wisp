import Foundation

/// One `hidutil` UserKeyMapping entry: a HID usage remapped to another.
public struct KeyMapping: Sendable, Hashable {
    public var source: UInt64
    public var destination: UInt64

    public init(source: UInt64, destination: UInt64) {
        self.source = source
        self.destination = destination
    }

    /// Caps Lock remapped to F18, which then acts as the Hyper modifier.
    public static let capsLockToF18 = KeyMapping(source: HIDUsage.capsLock, destination: HIDUsage.f18)
}

/// Keyboard usage IDs (usage page 0x07) in the form `hidutil` expects. See Apple TN2450.
public enum HIDUsage {
    public static let capsLock: UInt64 = 0x7_0000_0039
    public static let f18: UInt64 = 0x7_0000_006D
}

/// Reads and writes the `UserKeyMapping` property used by `/usr/bin/hidutil`.
public enum KeyMappingCodec {
    /// Parses `hidutil property --get UserKeyMapping` output: "(null)" or an old-style
    /// plist array of `{ HIDKeyboardModifierMappingDst = ...; HIDKeyboardModifierMappingSrc = ...; }`.
    /// hidutil prints one block per HID service, so repeated mappings are collapsed (order kept).
    public static func parse(_ output: String) -> [KeyMapping] {
        var seen = Set<KeyMapping>()
        return output.split(separator: "{").dropFirst().compactMap { block in
            guard let src = value(of: "HIDKeyboardModifierMappingSrc", in: block),
                let dst = value(of: "HIDKeyboardModifierMappingDst", in: block)
            else { return nil }
            let mapping = KeyMapping(source: src, destination: dst)
            return seen.insert(mapping).inserted ? mapping : nil
        }
    }

    /// JSON for `hidutil property --set`.
    public static func encode(_ mappings: [KeyMapping]) -> String {
        let entries = mappings.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}"
        }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    /// Adds `mapping`, replacing any existing entry for the same source key and
    /// keeping everything else the user already had.
    public static func adding(_ mapping: KeyMapping, to existing: [KeyMapping]) -> [KeyMapping] {
        existing.filter { $0.source != mapping.source } + [mapping]
    }

    /// Removes exactly `mapping`, leaving other entries (including other remaps of
    /// the same key made by someone else) untouched.
    public static func removing(_ mapping: KeyMapping, from existing: [KeyMapping]) -> [KeyMapping] {
        existing.filter { $0 != mapping }
    }

    private static func value(of key: String, in block: Substring) -> UInt64? {
        guard let keyRange = block.range(of: key),
            let equals = block[keyRange.upperBound...].firstIndex(of: "=")
        else { return nil }
        let rest = block[block.index(after: equals)...]
        let token = rest.prefix { $0 != ";" && $0 != "," && $0 != "}" }.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("0x") {
            return UInt64(token.dropFirst(2), radix: 16)
        }
        return UInt64(token)
    }
}
