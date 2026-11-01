/// Wisp's settings moved from the `com.maestro.wisp` domain to `com.ayomideodewale.wisp`.
/// On first launch under the new ID they are copied over once; the old plist stays put.
public enum LegacyDefaults {
    public static let oldDomain = "com.maestro.wisp"
    public static let importedFlagKey = "didImportLegacyDefaults"

    /// Wisp's own keys. AppKit window state and system keys belong to the old process.
    public static func shouldCopy(key: String) -> Bool {
        let systemPrefixes = ["NS", "Apple", "com.apple."]
        return key != importedFlagKey && !systemPrefixes.contains { key.hasPrefix($0) }
    }

    public static func entriesToCopy<Value>(from old: [String: Value]) -> [String: Value] {
        old.filter { shouldCopy(key: $0.key) }
    }
}
